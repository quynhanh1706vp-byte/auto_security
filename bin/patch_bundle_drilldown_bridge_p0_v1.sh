#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_commercial_v2.js"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_drill_bridge_${TS}"
echo "[BACKUP] $F.bak_drill_bridge_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_DRILLDOWN_BRIDGE_P0_V1"
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

patch = r'''
/* ===================== VSP_DRILLDOWN_BRIDGE_P0_V1 ===================== */
(function(){
  'use strict';
  try{
    // Ensure single entrypoint exists
    if (typeof window.VSP_DRILLDOWN !== 'function') {
      window.VSP_DRILLDOWN = function(intent){
        try{
          console.warn('[VSP][P0] VSP_DRILLDOWN missing impl; fallback intent=', intent);
          // Safe fallback: open datasource tab
          if (intent && typeof intent === 'object') {
            if (intent.intent === 'datasource' || intent.intent === 'total' || intent.intent === 'artifacts') {
              if (location && typeof location.hash === 'string') location.hash = '#datasource';
            }
          }
        }catch(_){}
      };
    }

    function wrap(name, intentName){
      if (typeof window[name] === 'function') return;
      window[name] = function(){
        try{
          return window.VSP_DRILLDOWN({ intent: intentName, args: Array.prototype.slice.call(arguments) });
        }catch(e){
          try{ console.warn('[VSP][P0] '+name+' failed', e); }catch(_){}
        }
      };
    }

    // Fix the exact crash you are seeing
    wrap('VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2', 'artifacts');

    // Optional: prevent future “not a function” on other pills/buttons
    wrap('VSP_DASH_DRILLDOWN_TOTAL_P1_V2', 'total');
    wrap('VSP_DASH_DRILLDOWN_CRITICAL_P1_V2', 'critical');
    wrap('VSP_DASH_DRILLDOWN_HIGH_P1_V2', 'high');
    wrap('VSP_DASH_DRILLDOWN_MEDIUM_P1_V2', 'medium');
    wrap('VSP_DASH_DRILLDOWN_LOW_P1_V2', 'low');
    wrap('VSP_DASH_DRILLDOWN_INFO_P1_V2', 'info');
    wrap('VSP_DASH_DRILLDOWN_TRACE_P1_V2', 'trace');

    console.log('[VSP][P0] drilldown bridge installed');
  }catch(_){}
})();
'''
p.write_text(s + "\n" + patch + "\n", encoding="utf-8")
print("[OK] appended", MARK)
PY

node --check "$F" && echo "[OK] node --check OK"
echo "== DONE =="
echo "[NEXT] restart 8910 + Ctrl+Shift+R"
