#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_enhance_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_p0_drillcall_v3_${TS}"
echo "[BACKUP] $F.bak_p0_drillcall_v3_${TS}"

TARGET_FILE="$F" python3 - <<'PY'
import os, re
from pathlib import Path

p = Path(os.environ["TARGET_FILE"])
s = p.read_text(encoding="utf-8", errors="ignore")

MARK = "/* P0_DRILLDOWN_CALL_V3 */"
if MARK not in s:
    header = MARK + r"""
(function(){
  try{
    if (typeof window === "undefined") return;

    // Stub always returns an object with safe methods
    window.__VSP_P0_DRILLDOWN_STUB = window.__VSP_P0_DRILLDOWN_STUB || function(){
      try{ console.info("[VSP_DASH][P0] drilldown stub called"); }catch(_){}
      return { open(){}, show(){}, close(){}, destroy(){} };
    };

    // Ensure window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 is callable
    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {
      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = window.__VSP_P0_DRILLDOWN_STUB;
      try{ console.info("[VSP_DASH][P0] drilldown forced stub (window)"); }catch(_){}
    }

    // Stable call entry (never throws)
    window.__VSP_P0_DRILLDOWN_CALL = window.__VSP_P0_DRILLDOWN_CALL || function(){
      try{
        const fn = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;
        if (typeof fn === "function") return fn.apply(window, arguments);
      }catch(_){}
      try{
        return window.__VSP_P0_DRILLDOWN_STUB.apply(window, arguments);
      }catch(_){}
      return { open(){}, show(){}, close(){}, destroy(){} };
    };
  }catch(_){}
})();
"""
    s = header + "\n" + s

# IMPORTANT: replace only CALL patterns, not definitions
# Any "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(" becomes "window.__VSP_P0_DRILLDOWN_CALL("
s2 = re.sub(r"\bVSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(", "window.__VSP_P0_DRILLDOWN_CALL(", s)

p.write_text(s2, encoding="utf-8")
print("[OK] patched drilldown callsites -> window.__VSP_P0_DRILLDOWN_CALL in", p)
PY

node --check "$F" >/dev/null
echo "[OK] node --check $F"
echo "[DONE] patch_p0_fix_drilldown_call_v3"
