#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
echo "[TS]=$TS"

patch_one(){
  local T="$1"
  [ -f "$T" ] || return 0
  cp -f "$T" "$T.bak_p0_dd_lock_${TS}"
  echo "[BACKUP] $T.bak_p0_dd_lock_${TS}"

  python3 - "$T" <<'PY'
import sys, re
from pathlib import Path

t = Path(sys.argv[1])
s = t.read_text(encoding="utf-8", errors="ignore")

MARK = "P0_DD_GLOBAL_LOCK_HEAD_V1"
if MARK in s:
    print("[OK] already locked:", t)
    sys.exit(0)

LOCK = r'''
<script>
/* P0_DD_GLOBAL_LOCK_HEAD_V1 */
(function(){
  try{
    if (typeof window === "undefined") return;

    // store real impl here if any script sets it correctly
    if (typeof window.__vsp_dd_real !== "function") window.__vsp_dd_real = null;

    function __vsp_dd_stub(){
      try{ console.info("[VSP][P0] drilldown stub invoked"); }catch(_){}
      return {open:function(){},show:function(){},close:function(){},destroy:function(){}};
    }

    function __vsp_dd_get(){
      return (typeof window.__vsp_dd_real === "function") ? window.__vsp_dd_real : __vsp_dd_stub;
    }

    // LOCK: always returns a function; ignores non-function overwrites
    try{
      Object.defineProperty(window, "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2", {
        configurable: false,
        enumerable: true,
        get: function(){ return __vsp_dd_get(); },
        set: function(v){
          if (typeof v === "function") {
            window.__vsp_dd_real = v;
            try{ console.info("[VSP][P0] drilldown real impl accepted"); }catch(_){}
          } else {
            try{ console.warn("[VSP][P0] blocked drilldown overwrite (non-function):", v); }catch(_){}
          }
        }
      });
    }catch(e){
      // if defineProperty fails, fallback: force function value
      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = __vsp_dd_get();
    }

    // ensure initial value is callable
    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {
      window.__vsp_dd_real = null;
    }
  }catch(_){}
})();
</script>
'''

# insert right after <head> (best), else after <body>
if "<head" in s:
    s2 = re.sub(r"(<head[^>]*>)", r"\1\n"+LOCK+"\n", s, count=1, flags=re.I)
else:
    s2 = re.sub(r"(<body[^>]*>)", r"\1\n"+LOCK+"\n", s, count=1, flags=re.I)

t.write_text(s2, encoding="utf-8")
print("[OK] inserted lock into", t)
PY
}

# apply to main dashboard template(s)
patch_one "templates/vsp_dashboard_2025.html"
patch_one "templates/vsp_4tabs_commercial_v1.html"

echo "[DONE] dd global lock v1"
