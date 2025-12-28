#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_row_actions_${TS}"
echo "[BACKUP] ${JS}.bak_row_actions_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

inject = r"""
/* VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V1
   - Per-row buttons: TGZ reports / CSV / SHA256 verify
   - DOM enhancer (MutationObserver) + light restart/backoff banner (no console spam)
*/
;(()=>{

  const MARK = "VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V1";
  const SHA_NAME_DEFAULT = "reports/run_gate_summary.json";

  // ---- tiny helpers
  const qs = (sel, root=document)=> root.querySelector(sel);
  const qsa = (sel, root=document)=> Array.from(root.querySelectorAll(sel));
  const esc = (x)=> (""+x).replace(/[&<>"']/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c]));
  const sleep = (ms)=> new Promise(r=>setTimeout(r, ms));

  function apiBase(){
    // same-origin by default
    return "";
  }
  function url_tgz(rid){ return `${apiBase()}/api/vsp/export_tgz?rid=${encodeURIComponent(rid)}&scope=reports`; }
  function url_csv(rid){ return `${apiBase()}/api/vsp/export_csv?rid=${encodeURIComponent(rid)}`; }
  function url_sha(rid, name){ return `${apiBase()}/api/vsp/sha256?rid=${encodeURIComponent(rid)}&name=${encodeURIComponent(name)}`; }

  // ---- style (kept subtle, dark-friendly)
  function ensureStyle(){
    if (qs("#vsp_rr_row_actions_style")) return;
    const st=document.createElement("style");
    st.id="vsp_rr_row_actions_style";
    st.textContent = `
      .vsp-rr-actions{ white-space:nowrap; display:flex; gap:8px; align-items:center; justify-content:flex-end; }
      .vsp-rr-btn{ font: 12px/1.2 ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Arial; padding:6px 10px; border-radius:10px;
                   border:1px solid rgba(255,255,255,.14); background:rgba(255,255,255,.06); color:inherit; text-decoration:none; cursor:pointer; }
      .vsp-rr-btn:hover{ background:rgba(255,255,255,.10); }
      .vsp-rr-btn:active{ transform: translateY(1px); }
      .vsp-rr-btn--ghost{ background:transparent; }
      .vsp-rr-toast{
        position:fixed; right:18px; bottom:18px; z-index:99999;
        max-width:560px; padding:12px 14px; border-radius:14px;
        background:rgba(0,0,0,.78); border:1px solid rgba(255,255,255,.16); color:#fff;
        box-shadow: 0 12px 34px rgba(0,0,0,.45);
      }
      .vsp-rr-toast pre{ margin:8px 0 0; white-space:pre-wrap; word-break:break-word; font-size:12px; opacity:.95; }
      .vsp-rr-banner{
        position:sticky; top:0; z-index:9999; margin:0 0 10px 0;
        padding:10px 12px; border-radius:14px;
        background:rgba(255,173,51,.12); border:1px solid rgba(255,173,51,.35);
        display:none;
      }
      .vsp-rr-banner b{ margin-right:8px; }
    `;
    document.head.appendChild(st);
  }

  function toast(title, bodyObj){
    const el=document.createElement("div");
    el.className="vsp-rr-toast";
    el.innerHTML = `<div><b>${esc(title)}</b></div>` + (bodyObj ? `<pre>${esc(JSON.stringify(bodyObj, null, 2))}</pre>` : "");
    document.body.appendChild(el);
    setTimeout(()=>{ el.style.opacity="0"; el.style.transition="opacity .25s ease"; }, 5500);
    setTimeout(()=>{ el.remove(); }, 6000);
  }

  // ---- banner for restart/backoff
  let bannerEl=null;
  function ensureBanner(){
    if (bannerEl && bannerEl.isConnected) return bannerEl;
    // Try to place near the runs table container if possible; fallback to body top.
    bannerEl=document.createElement("div");
    bannerEl.className="vsp-rr-banner";
    bannerEl.innerHTML = `<b>Service restarting…</b><span>UI will retry with backoff.</span>`;
    // best-effort insertion
    const host = qs("#runs") || qs("[data-tab='runs']") || qs(".runs") || document.body;
    host.prepend(bannerEl);
    return bannerEl;
  }
  function showBanner(msg){
    const b=ensureBanner();
    if (msg) b.querySelector("span").textContent = msg;
    b.style.display="block";
  }
  function hideBanner(){
    if (!bannerEl) return;
    bannerEl.style.display="none";
  }

  // ---- RID extraction: try dataset -> known classes -> first td text
  function getRidFromRow(tr){
    if (!tr || !(tr instanceof HTMLElement)) return "";
    const ds = tr.dataset || {};
    if (ds.rid) return (""+ds.rid).trim();
    const ridCell = tr.querySelector("td.rid, td[data-field='run_id'], td[data-col='run_id'], td:nth-child(1)");
    const txt = (ridCell ? ridCell.textContent : tr.textContent || "").trim();
    // heuristic: run_id is usually the first cell; trim to first token line
    const line = (txt.split("\n")[0] || "").trim();
    // avoid A2Z_INDEX
    if (!line || line === "A2Z_INDEX") return "";
    // keep it if length looks like an id
    if (line.length >= 8) return line;
    return "";
  }

  function ensureActionsCell(tr, rid){
    if (!rid) return;
    if (tr.querySelector("td.vsp-rr-actions-td")) return;

    const td=document.createElement("td");
    td.className="vsp-rr-actions-td";
    td.style.textAlign="right";

    const wrap=document.createElement("div");
    wrap.className="vsp-rr-actions";

    const a1=document.createElement("a");
    a1.className="vsp-rr-btn";
    a1.textContent="TGZ reports";
    a1.href=url_tgz(rid);

    const a2=document.createElement("a");
    a2.className="vsp-rr-btn vsp-rr-btn--ghost";
    a2.textContent="CSV";
    a2.href=url_csv(rid);

    const b3=document.createElement("button");
    b3.type="button";
    b3.className="vsp-rr-btn vsp-rr-btn--ghost";
    b3.textContent="SHA256 verify";
    b3.addEventListener("click", async (ev)=>{
      ev.preventDefault();
      b3.disabled=true;
      try{
        const r=await fetch(url_sha(rid, SHA_NAME_DEFAULT), { credentials:"same-origin" });
        const j=await r.json().catch(()=>({ok:false, err:"bad_json"}));
        if (!r.ok || !j || j.ok !== true){
          toast("SHA256 verify: FAIL", { rid, name: SHA_NAME_DEFAULT, http_ok: r.ok, json: j });
        }else{
          toast("SHA256 verify: OK", j);
        }
      }catch(e){
        toast("SHA256 verify: ERROR", { rid, err: (e && e.message) ? e.message : String(e) });
      }finally{
        b3.disabled=false;
      }
    });

    wrap.appendChild(a1);
    wrap.appendChild(a2);
    wrap.appendChild(b3);
    td.appendChild(wrap);
    tr.appendChild(td);
  }

  function findRunsTable(){
    // best-effort selectors
    return qs("table#runs_table")
        || qs("table[data-vsp-runs]")
        || qs("#runs table")
        || qs("[data-tab='runs'] table")
        || qs(".runs table")
        || null;
  }

  function patchRows(){
    ensureStyle();
    const tbl=findRunsTable();
    if (!tbl) return;
    const rows=qsa("tbody tr", tbl);
    if (!rows.length) return;

    for (const tr of rows){
      const rid=getRidFromRow(tr);
      if (!rid) continue;
      ensureActionsCell(tr, rid);
    }
  }

  // Observe DOM changes (so if table re-renders, actions re-attach)
  let mo=null;
  function startObserver(){
    if (mo) return;
    mo = new MutationObserver(()=>{
      try{ patchRows(); }catch(_){}
    });
    mo.observe(document.documentElement, { subtree:true, childList:true });
  }

  // Light health/backoff only when runs table exists (prevents global spam)
  let backoffMs=800;
  let healthLoopRunning=false;

  async function healthLoop(){
    if (healthLoopRunning) return;
    healthLoopRunning=true;

    for(;;){
      try{
        // run only when page visible and runs table exists
        if (document.visibilityState !== "visible"){
          await sleep(1200);
          continue;
        }
        if (!findRunsTable()){
          await sleep(1200);
          continue;
        }

        const r=await fetch(`${apiBase()}/api/vsp/runs?limit=1`, { credentials:"same-origin" });
        if (!r.ok){
          showBanner(`API not ready (${r.status}). Retrying…`);
          backoffMs = Math.min(15000, Math.floor(backoffMs*1.6));
          await sleep(backoffMs);
          continue;
        }
        // ok => hide banner & reset backoff
        hideBanner();
        backoffMs=800;
        await sleep(3500);
      }catch(_e){
        // swallow errors (avoid console spam), show banner + backoff
        showBanner("API unreachable. Retrying with backoff…");
        backoffMs = Math.min(15000, Math.floor(backoffMs*1.6));
        await sleep(backoffMs);
      }
    }
  }

  function boot(){
    try{
      patchRows();
      startObserver();
      healthLoop(); // intentionally fire-and-forget
    }catch(_){}
  }

  if (document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", boot, { once:true });
  }else{
    boot();
  }

})(); // IIFE
"""

# append at end (safe, minimal intrusion)
s2 = s.rstrip() + "\n\n" + inject + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended:", MARK)
PY

if [ "${HAS_NODE:-0}" = "1" ]; then
  node --check "$JS" >/dev/null
  echo "[OK] node --check OK"
else
  echo "[WARN] node not found; skipped syntax check"
fi

# restart if systemd service exists; otherwise just print hint
if command -v systemctl >/dev/null 2>&1 && systemctl list-units --type=service --all | grep -q 'vsp-ui-8910.service'; then
  sudo systemctl restart vsp-ui-8910.service
  echo "[OK] restarted: vsp-ui-8910.service"
else
  echo "[NOTE] restart manually (no systemd unit detected): restart your gunicorn/UI process"
fi

echo "[DONE] patch applied: VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V1"
