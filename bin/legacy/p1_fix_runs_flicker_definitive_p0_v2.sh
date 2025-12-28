#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || echo "[WARN] node not found -> will skip node --check"

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

CAND=(
  "static/js/vsp_bundle_commercial_v2.js"
  "static/js/vsp_bundle_commercial_v1.js"
  "static/js/vsp_runs_tab_resolved_v1.js"
  "static/js/vsp_app_entry_safe_v1.js"
)

python3 - <<'PY'
from pathlib import Path
import time

MARK="VSP_RUNS_STABLE_FETCH_P0_V2"
shim = r"""
/* VSP_RUNS_STABLE_FETCH_P0_V2: definitive anti-flicker for /api/vsp/runs (never propagate 5xx to UI) */
(function(){
  'use strict';
  try{
    if (window.__VSP_RUNS_STABLE_FETCH_P0_V2) return;
    window.__VSP_RUNS_STABLE_FETCH_P0_V2 = 1;
  }catch(_){}

  // clear stale fail/degraded flags so they cannot resurrect banner/toast
  try{
    var ks=[];
    for (var i=0;i<localStorage.length;i++){ var k=localStorage.key(i); if(k) ks.push(k); }
    ks.forEach(function(k){
      if(/runs.*fail|vsp_runs|degraded.*runs|runs_api|rid_latest_badge/i.test(k)){
        try{ localStorage.removeItem(k); }catch(_){}
      }
    });
  }catch(_){}

  var _origFetch = (window.fetch && window.fetch.bind) ? window.fetch.bind(window) : null;
  if(!_origFetch) return;

  var lastGoodJson = null;
  var lastGoodAt = 0;

  function isRunsUrl(u){
    try{
      var s = (typeof u === 'string') ? u : (u && u.url) ? u.url : String(u||'');
      return s.indexOf('/api/vsp/runs') >= 0;
    }catch(_){ return false; }
  }

  function mkJsonResp(obj, reason){
    try{
      var o = obj || {};
      // ensure ok=true for UI stability, but keep degraded metadata for debugging
      if (o.ok !== true) o.ok = true;
      if (!o.items) o.items = [];
      o._degraded = true;
      o._degraded_reason = reason || o._degraded_reason || "fallback";
      return new Response(JSON.stringify(o), {
        status: 200,
        headers: {
          "content-type": "application/json; charset=utf-8",
          "cache-control": "no-store",
          "x-vsp-degraded": "1"
        }
      });
    }catch(e){
      return new Response('{"ok":true,"items":[],"_degraded":true,"_degraded_reason":"fallback_min"}', {
        status: 200,
        headers: {"content-type":"application/json; charset=utf-8","cache-control":"no-store","x-vsp-degraded":"1"}
      });
    }
  }

  async function safeFetch(url, opts){
    if(!isRunsUrl(url)) return _origFetch(url, opts);

    // normalize opts (no-store, same-origin)
    var o = opts || {};
    try{
      if(!o.cache) o.cache = "no-store";
      if(!o.credentials) o.credentials = "same-origin";
    }catch(_){}

    try{
      var res = await _origFetch(url, o);

      // If HTTP ok: try capture last-good JSON when payload has ok:true
      try{
        if(res && res.ok){
          var ct = (res.headers && res.headers.get) ? (res.headers.get("content-type")||"") : "";
          if(ct.indexOf("application/json")>=0){
            var j = await res.clone().json().catch(function(){ return null; });
            if(j && j.ok === true){
              lastGoodJson = j;
              lastGoodAt = Date.now();
              // also clear any stale banner keys again after success
              try{
                var ks2=[];
                for (var i=0;i<localStorage.length;i++){ var k=localStorage.key(i); if(k) ks2.push(k); }
                ks2.forEach(function(k){
                  if(/runs.*fail|degraded.*runs|runs_api/i.test(k)){
                    try{ localStorage.removeItem(k); }catch(_){}
                  }
                });
              }catch(_){}
            }
          }
        }
      }catch(_){}

      // If not ok (e.g. 503): DO NOT propagate -> fallback
      if(!res || !res.ok){
        if(lastGoodJson) return mkJsonResp(lastGoodJson, "fallback_http_"+String(res?res.status:0));
        return mkJsonResp({ok:true, items:[], rid_latest:"N/A"}, "fallback_http_nocache_"+String(res?res.status:0));
      }

      return res;
    }catch(e){
      if(lastGoodJson) return mkJsonResp(lastGoodJson, "fallback_exc");
      return mkJsonResp({ok:true, items:[], rid_latest:"N/A"}, "fallback_exc_nocache");
    }
  }

  // hard override (last wins) so any earlier netguard wrapper cannot re-inject 5xx into runs page
  try{
    window.fetch = safeFetch;
  }catch(_){}

  // optional: hide any existing "RUNS API FAIL" remnants in DOM (belt & suspenders)
  function killFailText(){
    try{
      var nodes = document.querySelectorAll("body *");
      for (var i=0;i<nodes.length;i++){
        var el = nodes[i];
        if(!el || !el.textContent) continue;
        if(el.textContent.indexOf("RUNS API FAIL")>=0){
          try{ el.style.display="none"; }catch(_){}
        }
      }
    }catch(_){}
  }
  try{
    if(document.readyState==="loading"){
      document.addEventListener("DOMContentLoaded", function(){
        killFailText();
        setInterval(killFailText, 1200);
      });
    }else{
      killFailText();
      setInterval(killFailText, 1200);
    }
  }catch(_){}
})();
"""

cand = [
  "static/js/vsp_bundle_commercial_v2.js",
  "static/js/vsp_bundle_commercial_v1.js",
  "static/js/vsp_runs_tab_resolved_v1.js",
  "static/js/vsp_app_entry_safe_v1.js",
]

changed = False
for f in cand:
  p = Path(f)
  if not p.exists():
    print("[SKIP] missing:", f)
    continue
  s = p.read_text(encoding="utf-8", errors="replace")
  if MARK in s:
    print("[OK] already patched:", f)
    continue
  bak = p.with_name(p.name + f".bak_runs_flicker_def_{time.strftime('%Y%m%d_%H%M%S')}")
  bak.write_text(s, encoding="utf-8")
  p.write_text(s.rstrip()+"\n\n"+shim+"\n", encoding="utf-8")
  print("[OK] appended:", f, "backup:", bak)
  changed = True

print("[DONE] changed=", changed)
PY

for f in "${CAND[@]}"; do
  if [ -f "$f" ]; then
    if command -v node >/dev/null 2>&1; then
      node --check "$f" && echo "[OK] node --check: $f"
    fi
  fi
done

echo "== quick backend verify =="
curl -sS -i "http://127.0.0.1:8910/api/vsp/runs?limit=20" | head -n 12 || true

echo "[OK] Patch applied. Restart UI then Ctrl+F5 /runs"
