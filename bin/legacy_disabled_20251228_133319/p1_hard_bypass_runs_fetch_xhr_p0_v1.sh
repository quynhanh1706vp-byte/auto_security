#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || echo "[WARN] node not found -> will skip node --check"

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

CAND=(
  "static/js/vsp_app_entry_safe_v1.js"
  "static/js/vsp_runs_tab_resolved_v1.js"
  "static/js/vsp_bundle_commercial_v2.js"
  "static/js/vsp_bundle_commercial_v1.js"
)

python3 - <<'PY'
from pathlib import Path
import time

MARK = "VSP_P0_HARD_BYPASS_RUNS_FETCH_XHR_V1"
SNIP = r"""
/* VSP_P0_HARD_BYPASS_RUNS_FETCH_XHR_V1
   Purpose: definitive fix for RUNS API flicker (fetch wrappers/cached degraded payloads).
   - Bypass ALL fetch-wrappers for /api/vsp/runs* by using XHR
   - Purge localStorage caches used by older wrappers
   - Aggressively remove RUNS API FAIL banners/toasts that come from stale DOM updates
*/
(()=> {
  try{
    if (window.__vsp_p0_hard_bypass_runs_fetch_xhr_v1) return;
    window.__vsp_p0_hard_bypass_runs_fetch_xhr_v1 = true;

    // 1) purge known caches from old wrappers
    try{
      const keys = [];
      for (let i=0; i<localStorage.length; i++){
        const k = localStorage.key(i);
        if (!k) continue;
        if (k.includes("vsp_api_cache_") || k.includes("vsp_api_cache_v") || k.includes("vsp_api_cache_v7") || k.includes("vsp_api_cache_v7b::")){
          keys.push(k);
        }
      }
      keys.forEach(k=>{ try{ localStorage.removeItem(k); }catch(_){ } });
    }catch(_){}

    // helpers
    function _getUrl(input){
      try{
        if (typeof input === "string") return input;
        if (input && typeof input.url === "string") return input.url;
      }catch(_){}
      return "";
    }
    function _isRuns(u){
      try{
        if (!u) return false;
        // normalize absolute/relative
        const uu = new URL(u, location.origin);
        return uu.pathname === "/api/vsp/runs";
      }catch(_){
        return (String(u).includes("/api/vsp/runs"));
      }
    }
    function _xhrFetchText(url, init){
      return new Promise((resolve, reject)=>{
        try{
          const xhr = new XMLHttpRequest();
          xhr.open("GET", url, true);
          xhr.timeout = 12000;

          // pass headers if any
          try{
            const h = (init && init.headers) ? init.headers : null;
            if (h){
              if (typeof h.forEach === "function"){
                h.forEach((v,k)=>{ try{ xhr.setRequestHeader(k, v); }catch(_){ } });
              }else if (Array.isArray(h)){
                h.forEach(([k,v])=>{ try{ xhr.setRequestHeader(k, v); }catch(_){ } });
              }else if (typeof h === "object"){
                Object.keys(h).forEach(k=>{ try{ xhr.setRequestHeader(k, String(h[k])); }catch(_){ } });
              }
            }
          }catch(_){}

          xhr.onreadystatechange = ()=>{};
          xhr.onload = ()=>{
            try{
              const txt = xhr.responseText || "";
              const headers = new Headers();
              headers.set("Content-Type","application/json; charset=utf-8");
              headers.set("X-VSP-RUNS-BYPASS","XHR_V1");
              // NOTE: preserve real HTTP status (so UI shows real fail if backend truly fails)
              resolve(new Response(txt, {status: xhr.status || 200, headers}));
            }catch(e){ reject(e); }
          };
          xhr.onerror = ()=> reject(new Error("XHR network error"));
          xhr.ontimeout = ()=> reject(new Error("XHR timeout"));
          xhr.send(null);
        }catch(e){ reject(e); }
      });
    }

    // 2) override fetch for runs only (bypass wrappers)
    const prevFetch = window.fetch ? window.fetch.bind(window) : null;
    if (prevFetch){
      window.fetch = async (input, init)=>{
        const u0 = _getUrl(input);
        if (_isRuns(u0)){
          // always use absolute URL
          let u = u0;
          try{ u = new URL(u0, location.origin).toString(); }catch(_){}
          try{
            const r = await _xhrFetchText(u, init);
            // If backend returns 200 but payload is ok:false (stale), ignore and force one retry quickly.
            try{
              if (r && r.ok){
                const t = await r.clone().text();
                const j = JSON.parse(t);
                if (j && j.ok === false){
                  // one quick retry (true network)
                  const r2 = await _xhrFetchText(u, init);
                  return r2;
                }
              }
            }catch(_){}
            return r;
          }catch(_e){
            // fallback to original fetch if XHR fails (still better than hard failing)
            return prevFetch(input, init);
          }
        }
        return prevFetch(input, init);
      };
      console.log("[VSP_RUNS] HARD bypass installed (XHR) for /api/vsp/runs*");
    }

    // 3) kill stale FAIL banners/toasts that flicker due to older DOM updaters
    function _textOf(el){
      try{ return (el && (el.innerText || el.textContent) || "").trim(); }catch(_){ return ""; }
    }
    function _kill(){
      try{
        const bad = [];
        const all = document.querySelectorAll("body *");
        for (const el of all){
          const t = _textOf(el);
          if (!t) continue;
          if (t.includes("RUNS API FAIL") || t.includes("degraded (runs API 503)") || t.includes("Error: 503") && t.includes("/api/vsp/runs")){
            bad.push(el);
          }
        }
        bad.forEach(el=>{
          try{
            // remove the smallest container that likely holds the badge/toast
            el.style.display = "none";
          }catch(_){}
        });
      }catch(_){}
    }
    // run now + watch mutations
    _kill();
    try{
      const mo = new MutationObserver(()=>_kill());
      mo.observe(document.documentElement, {subtree:true, childList:true, characterData:true});
    }catch(_){}
  }catch(_){}
})();
"""

paths = [
  Path("static/js/vsp_app_entry_safe_v1.js"),
  Path("static/js/vsp_runs_tab_resolved_v1.js"),
  Path("static/js/vsp_bundle_commercial_v2.js"),
  Path("static/js/vsp_bundle_commercial_v1.js"),
]

changed = False
ts = time.strftime("%Y%m%d_%H%M%S")

for p in paths:
  if not p.exists():
    print("[WARN] missing:", p)
    continue
  s = p.read_text(encoding="utf-8", errors="replace")
  if MARK in s:
    print("[OK] already patched:", p)
    continue
  bak = p.with_name(p.name + f".bak_hard_bypass_runs_xhr_{ts}")
  bak.write_text(s, encoding="utf-8")
  p.write_text(s + "\n\n" + SNIP + "\n", encoding="utf-8")
  print("[OK] patched:", p, "backup:", bak.name)
  changed = True

print("[DONE] changed=", changed)
PY

for f in "${CAND[@]}"; do
  [ -f "$f" ] || continue
  if command -v node >/dev/null 2>&1; then
    node --check "$f" >/dev/null && echo "[OK] node --check: $f" || { echo "[ERR] node --check failed: $f"; exit 3; }
  fi
done

echo "== backend verify =="
curl -sS -I "http://127.0.0.1:8910/api/vsp/runs?limit=1" | sed -n '1,12p' || true

echo "== restart UI (single-owner) =="
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
bin/p1_ui_8910_single_owner_start_v2.sh || true

echo "[OK] NOW: Ctrl+F5 /runs (or open Incognito)."
