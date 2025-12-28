#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_enhance_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_p0_drill_local_v4_${TS}"
echo "[BACKUP] $F.bak_p0_drill_local_v4_${TS}"

TARGET_FILE="$F" python3 - <<'PY'
import os, re
from pathlib import Path

p = Path(os.environ["TARGET_FILE"])
s = p.read_text(encoding="utf-8", errors="ignore")

MARK = "/* P0_DRILLDOWN_LOCAL_V4 */"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

patch_block = MARK + r"""
  // P0: force local symbol to be FUNCTION (prevents "is not a function" even with shadowing)
  try{
    var __vsp_stub = function(){
      try{ console.info("[VSP_DASH][P0] drilldown stub called"); }catch(_){}
      return { open:function(){}, show:function(){}, close:function(){}, destroy:function(){} };
    };

    // local symbol (works even if calls are bare identifier)
    if (typeof VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {
      var VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = __vsp_stub; // var is function-scoped in IIFE
      try{ console.info("[VSP_DASH][P0] drilldown local stub armed"); }catch(_){}
    }

    // window symbol too (for other modules)
    if (typeof window !== "undefined" && typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {
      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;
      try{ console.info("[VSP_DASH][P0] drilldown window stub armed"); }catch(_){}
    }
  }catch(_){}
"""

# Insert right after first 'use strict';
m = re.search(r"([\"']use strict[\"'];\s*\n)", s)
if m:
    s = s[:m.end()] + patch_block + "\n" + s[m.end():]
else:
    # fallback: insert after first (function(){ line
    m2 = re.search(r"\(function\(\)\s*\{\s*\n", s)
    if m2:
        s = s[:m2.end()] + patch_block + "\n" + s[m2.end():]
    else:
        # last resort: prepend
        s = patch_block + "\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] patched", p)
PY

node --check "$F" >/dev/null
echo "[OK] node --check $F"
