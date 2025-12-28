#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

B="static/js/vsp_bundle_commercial_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$B" ] || { echo "[ERR] missing $B"; exit 2; }

cp -f "$B" "$B.bak_drillartv2_${TS}"
echo "[BACKUP] $B.bak_drillartv2_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_commercial_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# Heuristics: find DRILL_ART_V2 block by markers you have in Sources
start_candidates = [
  '/* find "Artifacts:" label */',
  '[DRILL_ART_V2]',
  'DRILL_ART_V2',
]
end_marker = '/* VSP_DASH_OPEN_REPORT_BTN_V1'

si = -1
for m in start_candidates:
  si = s.find(m)
  if si != -1:
    break

ei = s.find(end_marker, si if si != -1 else 0)

if si == -1 or ei == -1 or ei <= si:
  print("[ERR] cannot locate DRILL_ART_V2 block to replace.")
  print("[HINT] grep markers:")
  print("  grep -n \"DRILL_ART_V2\\|VSP_DASH_OPEN_REPORT_BTN_V1\" -n static/js/vsp_bundle_commercial_v1.js | head")
  raise SystemExit(2)

# Replace from si up to ei (keep the end_marker and remaining content)
safe = r'''
/* DRILL_ART_V2_REPLACED_P0_V1 (commercial safe) */
(function(){
  'use strict';

  // single public entrypoint
  if (typeof window.VSP_DRILLDOWN !== 'function') {
    window.VSP_DRILLDOWN = function(intent){
      try{
        // minimal safe behavior: go Data Source tab and store intent
        try{ localStorage.setItem("vsp_last_drilldown_intent_v1", JSON.stringify(intent||{})); }catch(_){}
        if (location && typeof location.hash === 'string') {
          // prefer datasource (table) for all drilldowns
          if (!location.hash.includes("datasource")) location.hash = "#datasource";
        }
        return true;
      }catch(e){ return false; }
    };
  }

  // hard legacy API (must be function)
  function dd(intent){ return window.VSP_DRILLDOWN(intent); }
  try{
    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = dd;
    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V1 = dd;
    window.VSP_DASH_DRILLDOWN_ARTIFACTS = dd;
  }catch(_){}

  // optional: silence noisy install logs
  try{ if(!window.__VSP_DD_ACCEPTED_ONCE){ window.__VSP_DD_ACCEPTED_ONCE=1; } }catch(_){}
})();
'''

new = s[:si] + safe + "\n\n" + s[ei:]
p.write_text(new, encoding="utf-8")
print("[OK] replaced DRILL_ART_V2 block:", "start=", si, "end=", ei, "bytes=", p.stat().st_size)
PY

echo "== node --check bundle =="
node --check "$B" && echo "[OK] bundle syntax OK"

echo "== DONE =="
echo "[NEXT] restart 8910 + Ctrl+Shift+R"
