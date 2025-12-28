#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_row_actions_v4_${TS}"
echo "[BACKUP] ${JS}.bak_row_actions_v4_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_runs_tab_resolved_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

def strip_block(text: str, marker: str) -> str:
    start = text.find(f"/* {marker}")
    if start < 0:
        return text
    end = text.find("})(); // IIFE", start)
    if end < 0:
        end = text.find("})();", start)
        if end < 0:
            return text[:start].rstrip() + "\n"
        end = end + len("})();")
        return (text[:start].rstrip() + "\n\n" + text[end:].lstrip())
    end = end + len("})(); // IIFE")
    return (text[:start].rstrip() + "\n\n" + text[end:].lstrip())

# remove older injected versions
for m in [
    "VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V1",
    "VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V2",
    "VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V3",
    "VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V4",
]:
    s = strip_block(s, m)

inject = r"""
/* VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V4
   - Per-row TGZ/CSV/SHA inside REPORTS cell
   - STOP DevTools spam during restart: cache+hold for /api/vsp/runs (both fetch + XHR)
   - Intercept fetch("<URL>") placeholder
*/
;(()=>{
  const MARK="VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V4";
  const SHA_NAME_DEFAULT="reports/run_gate_summary.json";

  // =========================
  // Network guard (fetch + XHR)
  // =========================
  (function vspNetworkGuard(){
    if (window.__vsp_netguard_p1v4) return;
    window.__vsp_netguard_p1v4 = true;

    const RUNS_CACHE_KEY="vsp_runs_cache_v1";
    let holdUntil = 0;

    function isRunsUrl(u){
      if (!u) return false;
      // match absolute or relative
      return (u.includes("/api/vsp/runs?") || u.endsWith("/api/vsp/runs") || u.includes("/api/vsp/runs&") || u.includes("/api/vsp/runs?limit="));
    }
    function loadCache(){
      try{
        const raw = localStorage.getItem(RUNS_CACHE_KEY);
        if (!raw) return null;
        return JSON.parse(raw);
      }catch(_){ return null; }
    }
    function saveCache(obj){
      try{ localStorage.setItem(RUNS_CACHE_KEY, JSON.stringify(obj)); }catch(_){}
    }
    function respJson(obj, headersExtra){
      const h = new Headers({ "Content-Type":"application/json; charset=utf-8" });
      try{
        if (headersExtra){
          for (const [k,v] of Object.entries(headersExtra)) h.set(k, String(v));
        }
      }catch(_){}
      return new Response(JSON.stringify(obj), { status: 200, headers: h });
    }

    // ---- fetch intercept
    const origFetch = window.fetch ? window.fetch.bind(window) : null;
    if (origFetch){
      window.fetch = async (input, init)=>{
        let u="";
        try{ u = (typeof input==="string") ? input : (input && input.url) ? input.url : ""; }catch(_){}

        // noisy placeholder
        if (u === "<URL>"){
          return respJson({ok:false, note:"intercepted <URL> placeholder", marker: MARK}, {"X-VSP-Intercept":"1"});
        }

        // runs cache+hold
        if (isRunsUrl(u)){
          const now=Date.now();
          if (now < holdUntil){
            const cached = loadCache() || {items:[], note:"degraded-cache-empty", ok:false};
            return respJson(cached, {"X-VSP-Cache":"1","X-VSP-Hold":"1"});
          }
          try{
            const r = await origFetch(input, init);
            if (r && r.ok){
              try{
                const j = await r.clone().json();
                if (j && typeof j==="object") saveCache(j);
              }catch(_){}
              return r;
            }
            holdUntil = Date.now() + 15000;
            const cached = loadCache() || {items:[], note:"degraded-cache-empty", ok:false};
            return respJson(cached, {"X-VSP-Cache":"1","X-VSP-Hold":"1","X-VSP-Non200": r ? r.status : "NA"});
          }catch(_e){
            holdUntil = Date.now() + 15000;
            const cached = loadCache() || {items:[], note:"degraded-cache-empty", ok:false};
            return respJson(cached, {"X-VSP-Cache":"1","X-VSP-Hold":"1","X-VSP-NetFail":"1"});
          }
        }

        return origFetch(input, init);
      };
    }

    // ---- XHR intercept (this is the one causing DevTools "Fetch failed loading" spam)
    if (window.XMLHttpRequest && XMLHttpRequest.prototype){
      const _open = XMLHttpRequest.prototype.open;
      const _send = XMLHttpRequest.prototype.send;

      XMLHttpRequest.prototype.open = function(method, url){
        try{ this.__vsp_url = url; }catch(_){}
        return _open.apply(this, arguments);
      };

      XMLHttpRequest.prototype.send = function(body){
        const u = (this && this.__vsp_url) ? String(this.__vsp_url) : "";
        if (isRunsUrl(u)){
          const now = Date.now();
          const cached = loadCache() || {items:[], note:"degraded-cache-empty", ok:false};

          // if in hold: short-circuit network => no spam in DevTools
          if (now < holdUntil){
            const txt = JSON.stringify(cached);
            try{
              // best-effort define readonly props
              Object.defineProperty(this, "status", {value:200, configurable:true});
              Object.defineProperty(this, "responseText", {value:txt, configurable:true});
              Object.defineProperty(this, "response", {value:txt, configurable:true});
            }catch(_){
              try{ this.status=200; this.responseText=txt; this.response=txt; }catch(__){}
            }

            const self=this;
            setTimeout(()=>{
              try{ self.readyState = 4; }catch(_){}
              try{ if (typeof self.onreadystatechange==="function") self.onreadystatechange(); }catch(_){}
              try{ if (typeof self.onload==="function") self.onload(); }catch(_){}
              try{ self.dispatchEvent && self.dispatchEvent(new Event("load")); }catch(_){}
            }, 0);
            return;
          }

          // wrap events to cache success / enter hold on failures
          const self=this;
          const onLoad = ()=>{
            try{
              if (self.status === 200){
                let j=null;
                try{ j = JSON.parse(self.responseText || "null"); }catch(_){}
                if (j && typeof j==="object") saveCache(j);
              }else{
                holdUntil = Date.now() + 15000;
              }
            }catch(_){}
          };
          const onErr = ()=>{ holdUntil = Date.now() + 15000; };

          try{ self.addEventListener("load", onLoad, {once:true}); }catch(_){}
          try{ self.addEventListener("error", onErr, {once:true}); }catch(_){}
          try{ self.addEventListener("timeout", onErr, {once:true}); }catch(_){}
        }

        return _send.apply(this, arguments);
      };
    }
  })();

  // =========================
  // UI: row actions (TGZ/CSV/SHA)
  // =========================
  const qs=(sel,root=document)=>root.querySelector(sel);
  const qsa=(sel,root=document)=>Array.from(root.querySelectorAll(sel));
  const esc=(x)=>(""+x).replace(/[&<>"']/g,c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c]));
  const apiBase=()=>""; // same-origin

  const url_tgz=(rid)=>`${apiBase()}/api/vsp/export_tgz?rid=${encodeURIComponent(rid)}&scope=reports`;
  const url_csv=(rid)=>`${apiBase()}/api/vsp/export_csv?rid=${encodeURIComponent(rid)}`;
  const url_sha=(rid,name)=>`${apiBase()}/api/vsp/sha256?rid=${encodeURIComponent(rid)}&name=${encodeURIComponent(name)}`;

  function ensureStyle(){
    if (qs("#vsp_rr_row_actions_style_v4")) return;
    const st=document.createElement("style");
    st.id="vsp_rr_row_actions_style_v4";
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

    reportTd.insertBefore(wrap, reportTd.firstChild);
  }

  function patchRows(){
    ensureStyle();
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

s = s.rstrip() + "\n\n" + inject + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] wrote: VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V4")
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

echo "[DONE] patch applied: VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V4"
