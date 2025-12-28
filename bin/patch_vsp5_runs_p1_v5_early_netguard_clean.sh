#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_p1_v5_${TS}"
echo "[BACKUP] ${JS}.bak_p1_v5_${TS}"

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

# strip old injections to avoid conflicts
for m in [
    "VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V1",
    "VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V2",
    "VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V3",
    "VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V4",
    "VSP_P1_NETGUARD_EARLY_V5",
    "VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V5",
]:
    s = strip_block(s, m)

early = r"""
/* VSP_P1_NETGUARD_EARLY_V5
   - MUST run before any poll captures fetch/XHR
   - Prevent DevTools spam during restart by cache+hold for /api/vsp/runs (fetch + XHR)
   - Intercept placeholder <URL> calls
   - Suppress noisy console logs ([VSP] poll down; backoff...) without hiding real errors
*/
;(()=>{
  if (window.__vsp_p1_netguard_early_v5) return;
  window.__vsp_p1_netguard_early_v5 = true;

  const RUNS_CACHE_KEY = "vsp_runs_cache_v1";
  let holdUntil = 0;

  const DROP = [
    /\[VSP\]\s*poll down; backoff/i,
    /Fetch failed loading/i,
    /ERR_CONNECTION/i,
    /runs fetch guard\/backoff enabled/i,
    /VSP_ROUTE_GUARD_RUNS_ONLY_/i,
    /runs_tab_resolved_v1\.js hash=/i,
  ];

  function isRunsUrl(u){
    if (!u) return false;
    return (u.includes("/api/vsp/runs?") || u.endsWith("/api/vsp/runs") || u.includes("/api/vsp/runs&") || u.includes("/api/vsp/runs?limit="));
  }
  function isPlaceholderUrl(u){
    if (!u) return false;
    return (u === "<URL>" || u.includes("<URL>"));
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

  // ---- console filter
  (function patchConsole(){
    if (window.__vsp_console_patched_v5) return;
    window.__vsp_console_patched_v5 = true;
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

  // ---- fetch wrapper (early)
  (function patchFetch(){
    if (!window.fetch || window.__vsp_fetch_patched_v5) return;
    window.__vsp_fetch_patched_v5 = true;
    const orig = window.fetch.bind(window);
    window.fetch = async (input, init)=>{
      let u="";
      try{ u = (typeof input==="string") ? input : (input && input.url) ? input.url : ""; }catch(_){}
      if (isPlaceholderUrl(u)){
        return respJson({ok:false, note:"intercepted <URL>", marker:"V5"}, {"X-VSP-Intercept":"1"});
      }
      if (isRunsUrl(u)){
        const now = Date.now();
        if (now < holdUntil){
          const cached = loadCache() || {items:[], ok:false, note:"degraded-cache-empty"};
          return respJson(cached, {"X-VSP-Cache":"1","X-VSP-Hold":"1"});
        }
        try{
          const r = await orig(input, init);
          if (r && r.ok){
            try{
              const j = await r.clone().json();
              if (j && typeof j === "object") saveCache(j);
            }catch(_){}
            return r;
          }
          holdUntil = Date.now() + 15000;
          const cached = loadCache() || {items:[], ok:false, note:"degraded-cache-empty"};
          return respJson(cached, {"X-VSP-Cache":"1","X-VSP-Hold":"1","X-VSP-Non200": r ? r.status : "NA"});
        }catch(_e){
          holdUntil = Date.now() + 15000;
          const cached = loadCache() || {items:[], ok:false, note:"degraded-cache-empty"};
          return respJson(cached, {"X-VSP-Cache":"1","X-VSP-Hold":"1","X-VSP-NetFail":"1"});
        }
      }
      return orig(input, init);
    };
  })();

  // ---- XHR wrapper (early) to stop DevTools XHR spam
  (function patchXHR(){
    if (!window.XMLHttpRequest || window.__vsp_xhr_patched_v5) return;
    window.__vsp_xhr_patched_v5 = true;

    const _open = XMLHttpRequest.prototype.open;
    const _send = XMLHttpRequest.prototype.send;

    XMLHttpRequest.prototype.open = function(method, url){
      try{ this.__vsp_url = String(url || ""); }catch(_){}
      return _open.apply(this, arguments);
    };

    XMLHttpRequest.prototype.send = function(body){
      const u = (this && this.__vsp_url) ? String(this.__vsp_url) : "";
      if (isPlaceholderUrl(u)){
        // short-circuit: no network
        const txt = JSON.stringify({ok:false, note:"intercepted <URL>", marker:"V5"});
        try{
          Object.defineProperty(this, "status", { get: ()=>200, configurable:true });
          Object.defineProperty(this, "responseText", { get: ()=>txt, configurable:true });
          Object.defineProperty(this, "response", { get: ()=>txt, configurable:true });
        }catch(_){}
        const self=this;
        setTimeout(()=>{
          try{ if (typeof self.onreadystatechange==="function") self.onreadystatechange(); }catch(_){}
          try{ if (typeof self.onload==="function") self.onload(); }catch(_){}
          try{ self.dispatchEvent && self.dispatchEvent(new Event("load")); }catch(_){}
        },0);
        return;
      }

      if (isRunsUrl(u)){
        const now = Date.now();
        if (now < holdUntil){
          const cached = loadCache() || {items:[], ok:false, note:"degraded-cache-empty"};
          const txt = JSON.stringify(cached);
          try{
            Object.defineProperty(this, "status", { get: ()=>200, configurable:true });
            Object.defineProperty(this, "responseText", { get: ()=>txt, configurable:true });
            Object.defineProperty(this, "response", { get: ()=>txt, configurable:true });
          }catch(_){}
          const self=this;
          setTimeout(()=>{
            try{ if (typeof self.onreadystatechange==="function") self.onreadystatechange(); }catch(_){}
            try{ if (typeof self.onload==="function") self.onload(); }catch(_){}
            try{ self.dispatchEvent && self.dispatchEvent(new Event("load")); }catch(_){}
          },0);
          return; // IMPORTANT: no network => no DevTools spam
        }

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
  })();
})(); // IIFE
"""

row_actions = r"""
/* VSP5_RUNS_REPORTS_ROW_ACTIONS_P1_V5
   - Per-row TGZ/CSV/SHA inside REPORTS cell (working stable)
*/
;(()=>{
  const SHA_NAME_DEFAULT="reports/run_gate_summary.json";
  const qs=(sel,root=document)=>root.querySelector(sel);
  const qsa=(sel,root=document)=>Array.from(root.querySelectorAll(sel));
  const esc=(x)=>(""+x).replace(/[&<>"']/g,c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c]));
  const apiBase=()=>""; // same-origin

  const url_tgz=(rid)=>`${apiBase()}/api/vsp/export_tgz?rid=${encodeURIComponent(rid)}&scope=reports`;
  const url_csv=(rid)=>`${apiBase()}/api/vsp/export_csv?rid=${encodeURIComponent(rid)}`;
  const url_sha=(rid,name)=>`${apiBase()}/api/vsp/sha256?rid=${encodeURIComponent(rid)}&name=${encodeURIComponent(name)}`;

  function ensureStyle(){
    if (qs("#vsp_rr_row_actions_style_v5")) return;
    const st=document.createElement("style");
    st.id="vsp_rr_row_actions_style_v5";
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

# Prepend EARLY netguard (must be before any code in file)
s = early.lstrip() + "\n\n" + s.lstrip()

# Append row actions at end
s = s.rstrip() + "\n\n" + row_actions + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] wrote: VSP_P1_NETGUARD_EARLY_V5 + ROW_ACTIONS_P1_V5")
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

echo "[DONE] patch applied: VSP_P1_NETGUARD_EARLY_V5"
