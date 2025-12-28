#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_row_actions_v2_${TS}"
echo "[BACKUP] ${JS}.bak_row_actions_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_runs_tab_resolved_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

OLD = "VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V1"
NEW = "VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V2"
if NEW in s:
    print("[SKIP] already patched:", NEW)
    raise SystemExit(0)

inject = r"""
/* VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V2
   - Per-row buttons go INSIDE existing REPORTS cell (no extra TD => không bị nuốt cột)
   - Console sạch: drop spam logs from poll/backoff + fetch-failed noise
*/
;(()=>{
  const MARK = "VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V2";
  const SHA_NAME_DEFAULT = "reports/run_gate_summary.json";

  // ---- console de-spam (commercial)
  (function patchConsole(){
    if (window.__vsp_console_patched_p1v2) return;
    window.__vsp_console_patched_p1v2 = true;

    const DROP = [
      /\[VSP\]\s*poll down; backoff/i,
      /Fetch failed loading/i,
      /ERR_CONNECTION/i,
      /runs fetch guard\/backoff enabled/i,
      /VSP_ROUTE_GUARD_RUNS_ONLY_/i,
      /runs_tab_resolved_v1\.js hash=/i,
    ];
    function shouldDrop(args){
      if (!args || !args.length) return false;
      const a0 = (typeof args[0] === "string") ? args[0] : "";
      return DROP.some(rx => rx.test(a0));
    }
    for (const k of ["log","info","warn","error"]){
      const orig = console[k].bind(console);
      console[k] = (...args)=>{
        try{ if (shouldDrop(args)) return; }catch(_){}
        return orig(...args);
      };
    }
  })();

  // ---- helpers
  const qs=(sel,root=document)=>root.querySelector(sel);
  const qsa=(sel,root=document)=>Array.from(root.querySelectorAll(sel));
  const esc=(x)=>(""+x).replace(/[&<>"']/g,c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c]));
  const apiBase=()=>""; // same-origin

  const url_tgz=(rid)=>`${apiBase()}/api/vsp/export_tgz?rid=${encodeURIComponent(rid)}&scope=reports`;
  const url_csv=(rid)=>`${apiBase()}/api/vsp/export_csv?rid=${encodeURIComponent(rid)}`;
  const url_sha=(rid,name)=>`${apiBase()}/api/vsp/sha256?rid=${encodeURIComponent(rid)}&name=${encodeURIComponent(name)}`;

  function ensureStyle(){
    if (qs("#vsp_rr_row_actions_style_v2")) return;
    const st=document.createElement("style");
    st.id="vsp_rr_row_actions_style_v2";
    st.textContent=`
      .vsp-rr-rowx{ display:inline-flex; gap:8px; align-items:center; margin-right:10px; }
      .vsp-rr-xbtn{
        font: 12px/1.15 ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Arial;
        padding:5px 10px; border-radius:999px; cursor:pointer; text-decoration:none;
        border:1px solid rgba(255,255,255,.16); background:rgba(255,255,255,.06); color:inherit;
      }
      .vsp-rr-xbtn:hover{ background:rgba(255,255,255,.10); }
      .vsp-rr-xbtn--ghost{ background:transparent; }
      .vsp-rr-toast{
        position:fixed; right:18px; bottom:18px; z-index:99999;
        max-width:560px; padding:12px 14px; border-radius:14px;
        background:rgba(0,0,0,.78); border:1px solid rgba(255,255,255,.16); color:#fff;
        box-shadow: 0 12px 34px rgba(0,0,0,.45);
      }
      .vsp-rr-toast pre{ margin:8px 0 0; white-space:pre-wrap; word-break:break-word; font-size:12px; opacity:.95; }
    `;
    document.head.appendChild(st);
  }

  function toast(title, body){
    const el=document.createElement("div");
    el.className="vsp-rr-toast";
    el.innerHTML=`<div><b>${esc(title)}</b></div>`+(body?`<pre>${esc(JSON.stringify(body,null,2))}</pre>`:"");
    document.body.appendChild(el);
    setTimeout(()=>{ el.style.opacity="0"; el.style.transition="opacity .25s ease"; }, 5200);
    setTimeout(()=>{ el.remove(); }, 5600);
  }

  function normHdr(t){ return (t||"").replace(/\s+/g," ").trim().toUpperCase(); }

  function findRunsTable(){
    const tables=qsa("table");
    for (const t of tables){
      const ths=qsa("thead th", t);
      if (!ths.length) continue;
      const hdrs=ths.map(th=>normHdr(th.textContent));
      if (hdrs.includes("RUN ID") && hdrs.includes("REPORTS")) return t;
    }
    return null;
  }

  function getReportColIndex(tbl){
    const ths=qsa("thead th", tbl);
    const hdrs=ths.map(th=>normHdr(th.textContent));
    return hdrs.indexOf("REPORTS");
  }

  function getRidFromRow(tr){
    const ds=tr.dataset||{};
    if (ds.rid) return (""+ds.rid).trim();
    const tds=qsa("td", tr);
    if (!tds.length) return "";
    const first=(tds[0].textContent||"").trim().split("\n")[0].trim();
    if (!first || first==="A2Z_INDEX") return "";
    return first;
  }

  function ensureRowButtons(rid, reportTd){
    if (!reportTd) return;
    if (reportTd.querySelector(".vsp-rr-rowx")) return;

    const wrap=document.createElement("span");
    wrap.className="vsp-rr-rowx";

    const aT=document.createElement("a");
    aT.className="vsp-rr-xbtn";
    aT.textContent="TGZ";
    aT.href=url_tgz(rid);

    const aC=document.createElement("a");
    aC.className="vsp-rr-xbtn vsp-rr-xbtn--ghost";
    aC.textContent="CSV";
    aC.href=url_csv(rid);

    const bS=document.createElement("button");
    bS.type="button";
    bS.className="vsp-rr-xbtn vsp-rr-xbtn--ghost";
    bS.textContent="SHA";
    bS.addEventListener("click", async (ev)=>{
      ev.preventDefault();
      bS.disabled=true;
      try{
        const r=await fetch(url_sha(rid, SHA_NAME_DEFAULT), {credentials:"same-origin"});
        const j=await r.json().catch(()=>({ok:false, err:"bad_json"}));
        if (!r.ok || !j || j.ok!==true){
          toast("SHA verify: FAIL", { rid, name: SHA_NAME_DEFAULT, http_ok: r.ok, json: j });
        }else{
          toast("SHA verify: OK", j);
        }
      }catch(e){
        toast("SHA verify: ERROR", { rid, err: (e&&e.message)?e.message:String(e) });
      }finally{
        bS.disabled=false;
      }
    });

    wrap.appendChild(aT);
    wrap.appendChild(aC);
    wrap.appendChild(bS);

    // prepend into REPORTS cell (không phá layout)
    reportTd.insertBefore(wrap, reportTd.firstChild);
  }

  function patchRows(){
    ensureStyle();

    // hide any old extra TD from V1 (nếu có)
    qsa("td.vsp-rr-actions-td").forEach(td=>{ try{ td.style.display="none"; }catch(_){} });

    const tbl=findRunsTable();
    if (!tbl) return;
    const idx=getReportColIndex(tbl);
    if (idx < 0) return;

    const rows=qsa("tbody tr", tbl);
    for (const tr of rows){
      const rid=getRidFromRow(tr);
      if (!rid) continue;
      const tds=qsa("td", tr);
      const reportTd = (idx < tds.length) ? tds[idx] : null;
      ensureRowButtons(rid, reportTd);
    }
  }

  // MutationObserver to re-apply when table re-renders
  let tmr=null;
  function schedule(){
    if (tmr) return;
    tmr=setTimeout(()=>{ tmr=null; try{ patchRows(); }catch(_){ } }, 120);
  }
  const mo=new MutationObserver(schedule);
  mo.observe(document.documentElement, {subtree:true, childList:true});

  if (document.readyState==="loading"){
    document.addEventListener("DOMContentLoaded", ()=>{ patchRows(); }, {once:true});
  }else{
    patchRows();
  }
})(); // IIFE
"""

if OLD in s:
    # replace old injected block (from its comment to end IIFE line)
    s2 = re.sub(
        r"/\*\s*VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V1[\s\S]*?\)\s*;\s*// IIFE\s*\n",
        inject + "\n",
        s,
        count=1
    )
    if s2 == s:
        # fallback: append
        s2 = s.rstrip() + "\n\n" + inject + "\n"
else:
    s2 = s.rstrip() + "\n\n" + inject + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] applied:", NEW)
PY

if [ "${HAS_NODE:-0}" = "1" ]; then
  node --check "$JS" >/dev/null
  echo "[OK] node --check OK"
else
  echo "[WARN] node not found; skipped syntax check"
fi

if command -v systemctl >/dev/null 2>&1 && systemctl list-units --type=service --all | grep -q 'vsp-ui-8910.service'; then
  sudo systemctl restart vsp-ui-8910.service
  echo "[OK] restarted: vsp-ui-8910.service"
else
  echo "[NOTE] restart manually (no systemd unit detected)"
fi

echo "[DONE] patch applied: VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V2"
