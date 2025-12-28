#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "== PATCH DRILLDOWN HARDLOCK (P0 v1) =="
echo "[TS] $TS"
echo "[PWD] $(pwd)"

B="static/js/vsp_bundle_commercial_v1.js"
[ -f "$B" ] || { echo "[ERR] missing $B"; exit 2; }

cp -f "$B" "$B.bak_dd_hardlock_${TS}"
echo "[BACKUP] $B.bak_dd_hardlock_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, datetime

p = Path("static/js/vsp_bundle_commercial_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) Rewrite callsites to safe wrapper (prevents "not a function" even if local var exists)
def wrap_call(name: str, txt: str) -> str:
  # Replace "NAME(" with "(window.NAME || window.VSP_DRILLDOWN || window.VSP_DRILLDOWN_IMPL || function(){return null;} )("
  repl = f"(window.{name} || window.VSP_DRILLDOWN || window.VSP_DRILLDOWN_IMPL || function(){{return null;}})("
  return txt.replace(f"{name}(", repl)

names = [
  "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2",
  "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V1",
  "VSP_DASH_DRILLDOWN_ARTIFACTS",
]
s2 = s
for nm in names:
  s2 = wrap_call(nm, s2)

# 2) Append hard-lock footer (ensures globals are functions and non-writable)
marker = "/* VSP_DRILLDOWN_HARDLOCK_FOOTER_P0_V1 */"
if marker not in s2:
  footer = r'''
/* VSP_DRILLDOWN_HARDLOCK_FOOTER_P0_V1 */
(function(){
  'use strict';
  function _dd(intent){
    try{
      if (typeof window.VSP_DRILLDOWN_IMPL === 'function') return window.VSP_DRILLDOWN_IMPL(intent);
      if (typeof window.VSP_DRILLDOWN === 'function') return window.VSP_DRILLDOWN(intent);
      return null;
    }catch(e){ return null; }
  }
  function hard(name){
    try{
      var f = function(intent){ return _dd(intent); };
      // lock symbol to function to prevent overwrite by legacy modules
      try{
        Object.defineProperty(window, name, {value:f, writable:false, configurable:false});
      }catch(_){
        window[name] = f;
      }
      // also keep legacy namespace compat
      try{ window.P1_V2 = window.P1_V2 || {}; window.P1_V2.drilldown = f; }catch(__){}
    }catch(_e){}
  }
  hard("VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2");
  hard("VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V1");
  hard("VSP_DASH_DRILLDOWN_ARTIFACTS");
})();
'''
  s2 = s2 + "\n" + footer + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] patched bundle (callsites wrapped + hardlock footer)")
PY

echo "== node --check bundle =="
node --check "$B" && echo "[OK] bundle syntax OK"

echo "== DONE =="
echo "[NEXT] restart 8910 + HARD refresh Ctrl+Shift+R, open /vsp4#dashboard + click drilldown"
