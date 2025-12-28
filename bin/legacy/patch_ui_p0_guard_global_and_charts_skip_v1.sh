#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
echo "[TS]=$TS"

# --- (A) Fix guard ReferenceError by defining global functions at TOP of vsp_dashboard_enhance_v1.js
F1="static/js/vsp_dashboard_enhance_v1.js"
if [ -f "$F1" ]; then
  cp -f "$F1" "$F1.bak_p0_guard_global_${TS}"
  echo "[BACKUP] $F1.bak_p0_guard_global_${TS}"

  python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_dashboard_enhance_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")

marker = "/* P0_GUARD_GLOBAL_V1 */"
if marker not in s:
    header = marker + r'''
// Define global guard so any callsite can see it (prevents ReferenceError)
(function(){
  try{
    if (typeof window === "undefined") return;

    window.VSP_DASH_IS_ACTIVE_P0 = window.VSP_DASH_IS_ACTIVE_P0 || function(){
      try{
        const h = (location.hash || "").toLowerCase();
        if (!h || h === "#" || h === "#dashboard") return true;
        return false;
      }catch(_){ return false; }
    };

    window.VSP_DASH_P0_GUARD = window.VSP_DASH_P0_GUARD || function(reason){
      try{
        if (!window.VSP_DASH_IS_ACTIVE_P0()){
          try{ console.info("[VSP_DASH][P0] skip:", reason, "hash=", location.hash); }catch(_){}
          return false;
        }
        return true;
      }catch(_){ return true; }
    };

    // Also provide plain global function names (some code calls them directly)
    if (typeof window.VSP_DASH_P0_GUARD === "function") {
      window.VSP_DASH_P0_GUARD_NAME = "ok";
    }
  }catch(_){}
})();

// Plain-name wrappers (avoid ReferenceError even if code calls VSP_DASH_P0_GUARD directly)
function VSP_DASH_IS_ACTIVE_P0(){ try{ return (window && window.VSP_DASH_IS_ACTIVE_P0) ? window.VSP_DASH_IS_ACTIVE_P0() : true; }catch(_){ return true; } }
function VSP_DASH_P0_GUARD(reason){ try{ return (window && window.VSP_DASH_P0_GUARD) ? window.VSP_DASH_P0_GUARD(reason) : true; }catch(_){ return true; } }

'''
    s = header + s

p.write_text(s, encoding="utf-8")
print("[OK] prepended global guard header")
PY

  node --check "$F1" >/dev/null
  echo "[OK] node --check $F1"
else
  echo "[SKIP] missing $F1"
fi

# --- (B) Skip chart bootstrap on non-dashboard hash to stop "give up after 20 tries" on #settings
F2="static/js/vsp_dashboard_charts_bootstrap_v1.js"
if [ -f "$F2" ]; then
  cp -f "$F2" "$F2.bak_p0_charts_skip_${TS}"
  echo "[BACKUP] $F2.bak_p0_charts_skip_${TS}"

  python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_charts_bootstrap_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")

marker = "/* P0_CHARTS_SKIP_NON_DASH_V1 */"
if marker not in s:
    # Insert early guard after 'use strict' if present, else at top
    guard = marker + r'''
(function(){
  try{
    const h = (location.hash || "").toLowerCase();
    if (h && h !== "#" && h !== "#dashboard") {
      try{ console.info("[VSP_CHARTS_BOOT][P0] skip (non-dashboard) hash=", h); }catch(_){}
      return;
    }
  }catch(_){}
})();
'''
    m = re.search(r"(?:\"use strict\";|'use strict';)\s*", s)
    if m:
        s = s[:m.end()] + "\n" + guard + s[m.end():]
    else:
        s = guard + "\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] injected charts skip guard")
PY

  node --check "$F2" >/dev/null
  echo "[OK] node --check $F2"
else
  echo "[SKIP] missing $F2"
fi

echo "[DONE] P0 guard global + charts skip applied"
