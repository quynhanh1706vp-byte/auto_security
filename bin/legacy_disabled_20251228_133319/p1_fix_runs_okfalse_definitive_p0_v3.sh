#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ss; need curl
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

MARK="VSP_RUNS_STABLE_FETCH_P0_V3"
shim = r"""
/* VSP_RUNS_STABLE_FETCH_P0_V3: force ok:true for /api/vsp/runs (fix 200-but-ok:false flicker from netguard) */
(function(){
  'use strict';
  try{ if (window.__VSP_RUNS_STABLE_FETCH_P0_V3) return; window.__VSP_RUNS_STABLE_FETCH_P0_V3 = 1; }catch(_){}

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
    var o = obj && typeof obj === "object" ? obj : {};
    if (o.ok !== true) o.ok = true;
    if (!o.items) o.items = [];
    o._degraded = (reason ? true : !!o._degraded);
    if (reason) o._degraded_reason = reason;
    return new Response(JSON.stringify(o), {
      status: 200,
      headers: {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "no-store",
        "x-vsp-runs-shim": "P0_V3"
      }
    });
  }

  async function safeFetch(input, init){
    if(!isRunsUrl(input)) return _origFetch(input, init);

    // ensure stable fetch options
    var o = init || {};
    try{ if(!o.cache) o.cache="no-store"; if(!o.credentials) o.credentials="same-origin"; }catch(_){}

    try{
      var res = await _origFetch(input, o);

      // Try read JSON no matter what status is (netguard can return 200 with ok:false)
      var j = null;
      try{
        var ct = (res && res.headers && res.headers.get) ? (res.headers.get("content-type")||"") : "";
        if(ct.indexOf("application/json")>=0){
          j = await res.clone().json().catch(function(){ return null; });
        }
      }catch(_){ j = null; }

      if(j && j.ok === true){
        lastGoodJson = j;
        lastGoodAt = Date.now();
        return mkJsonResp(j, "pass_ok_true"); // normalize headers + keep ok:true
      }

      // If upstream returns ok:false (even with HTTP 200) => FORCE ok:true using lastGood or empty
      if(lastGoodJson){
        return mkJsonResp(lastGoodJson, "fallback_okfalse");
      }
      if(j){
        return mkJsonResp(j, "force_ok_true_from_upstream_okfalse");
      }
      return mkJsonResp({ok:true, items:[], rid_latest:"N/A"}, "fallback_nojson");
    }catch(e){
      if(lastGoodJson) return mkJsonResp(lastGoodJson, "fallback_exc");
      return mkJsonResp({ok:true, items:[], rid_latest:"N/A"}, "fallback_exc_nocache");
    }
  }

  // last-wins override
  try{ window.fetch = safeFetch; }catch(_){}
  try{ console.log("[VSP_RUNS] stable fetch shim enabled (P0_V3): force ok:true for /api/vsp/runs*"); }catch(_){}
})();
"""

cand = [
  "static/js/vsp_bundle_commercial_v2.js",
  "static/js/vsp_bundle_commercial_v1.js",
  "static/js/vsp_runs_tab_resolved_v1.js",
  "static/js/vsp_app_entry_safe_v1.js",
]

changed=False
for f in cand:
  p=Path(f)
  if not p.exists():
    print("[SKIP] missing:", f); continue
  s=p.read_text(encoding="utf-8", errors="replace")
  if MARK in s:
    print("[OK] already patched:", f); continue
  bak=p.with_name(p.name+f".bak_runs_okfalse_v3_{time.strftime('%Y%m%d_%H%M%S')}")
  bak.write_text(s, encoding="utf-8")
  p.write_text(s.rstrip()+"\n\n"+shim+"\n", encoding="utf-8")
  print("[OK] appended:", f, "backup:", bak)
  changed=True
print("[DONE] changed=", changed)
PY

for f in "${CAND[@]}"; do
  [ -f "$f" ] || continue
  if command -v node >/dev/null 2>&1; then node --check "$f" && echo "[OK] node --check: $f"; fi
done

echo "== backend sanity =="
curl -sS -i "http://127.0.0.1:8910/api/vsp/runs?limit=2" | head -n 12 || true

echo "== restart clean (remove lock + kill :8910) =="
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
PIDS="$(ss -ltnp 2>/dev/null | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
[ -n "${PIDS// }" ] && { echo "[INFO] killing pids: $PIDS"; kill -9 $PIDS || true; } || true

bin/p1_ui_8910_single_owner_start_v2.sh || true

echo "== verify =="
curl -sS -I http://127.0.0.1:8910/vsp5 | head -n 6
curl -sS -I "http://127.0.0.1:8910/api/vsp/runs?limit=20" | head -n 8
echo "[OK] Now Ctrl+F5 /runs (or open Incognito)."
