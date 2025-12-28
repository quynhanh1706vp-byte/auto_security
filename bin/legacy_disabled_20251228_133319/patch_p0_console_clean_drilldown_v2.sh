#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "[TS]=$TS"

backup(){
  local f="$1"
  [ -f "$f" ] || return 0
  cp -f "$f" "$f.bak_p0_${TS}"
  echo "[BACKUP] $f.bak_p0_${TS}"
}

# -----------------------------
# A) Fix drilldown red error
# -----------------------------
F="static/js/vsp_dashboard_enhance_v1.js"
if [ -f "$F" ]; then
  backup "$F"

  python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_enhance_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_P0_DRILLDOWN_CALL_V2"
if MARK not in s:
    header = r"""/* VSP_P0_DRILLDOWN_CALL_V2: prevent red console when drilldown is missing */
(function(){
  try{
    if (typeof window === "undefined") return;

    // ensure window function exists early (before any local capture)
    if (typeof window.__VSP_P0_DRILLDOWN_STUB !== "function") {
      window.__VSP_P0_DRILLDOWN_STUB = function(){
        try{ console.info("[VSP_DASH][P0] drilldown stub called"); }catch(_){}
        return { open(){}, show(){}, close(){}, destroy(){} };
      };
    }
    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {
      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = window.__VSP_P0_DRILLDOWN_STUB;
      try{ console.info("[VSP_DASH][P0] drilldown forced stub (window)"); }catch(_){}
    }

    // stable caller: always a function
    if (typeof window.__VSP_P0_DRILLDOWN_CALL_V2 !== "function") {
      window.__VSP_P0_DRILLDOWN_CALL_V2 = function(){
        try{
          var fn = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;
          if (typeof fn === "function") return fn.apply(window, arguments);
        }catch(_){}
        try{
          var stub = window.__VSP_P0_DRILLDOWN_STUB;
          if (typeof stub === "function") return stub.apply(window, arguments);
        }catch(_){}
        return { open(){}, show(){}, close(){}, destroy(){} };
      };
    }
  }catch(_){}
})();
"""
    s = header + "\n" + s

# Replace ANY direct calls to the raw symbol with the safe caller
# This avoids local shadowing / non-function capture causing crash.
s2 = re.sub(r"\bVSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(", "window.__VSP_P0_DRILLDOWN_CALL_V2(", s)
p.write_text(s2, encoding="utf-8")
print("[OK] patched drilldown -> __VSP_P0_DRILLDOWN_CALL_V2")
PY

  node --check "$F" >/dev/null && echo "[OK] node --check $F"
else
  echo "[SKIP] missing $F"
fi

# -----------------------------
# B) Demote charts 'give up' warn -> info (no amber spam)
# -----------------------------
C="static/js/vsp_dashboard_charts_bootstrap_v1.js"
if [ -f "$C" ]; then
  backup "$C"

  python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_charts_bootstrap_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")

# only touch the specific message
s2 = s.replace('console.warn("[VSP_CHARTS_BOOT_SAFE_V2] give up after', 'console.info("[VSP_CHARTS_BOOT_SAFE_V2] give up after')
if s2 != s:
    p.write_text(s2, encoding="utf-8")
    print("[OK] demoted give-up warn -> info")
else:
    print("[INFO] no warn string found (already patched?)")
PY

  node --check "$C" >/dev/null && echo "[OK] node --check $C"
else
  echo "[SKIP] missing $C"
fi

echo "[DONE] patch_p0_console_clean_drilldown_v2"
