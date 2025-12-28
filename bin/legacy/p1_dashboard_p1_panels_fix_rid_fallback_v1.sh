#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_fix_rid_${TS}"
echo "[BACKUP] ${JS}.bak_fix_rid_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_DASHBOARD_P1_PANELS_V1"
if marker not in s:
    raise SystemExit("[ERR] P1 panels marker not found; did you apply the previous addon?")

# Replace the RID resolution block inside main()
# We look for: if (!rid){ try{ fetch rid_latest ... }catch{ show error; return; } }
pat = re.compile(
    r'let\s+rid\s*=\s*window\.__VSP_RID_LATEST_GATE_ROOT__.*?'
    r'if\s*\(\s*!\s*rid\s*\)\s*\{\s*try\s*\{.*?/api/vsp/rid_latest_gate_root.*?\}\s*catch\s*\(e\)\s*\{.*?Cannot resolve rid_latest_gate_root\..*?return;\s*\}\s*\}',
    re.S
)

m = pat.search(s)
if not m:
    raise SystemExit("[ERR] cannot locate old rid resolve block (pattern mismatch).")

new_block = r'''
    let rid = window.__VSP_RID_LATEST_GATE_ROOT__ || window.__vsp_rid_latest_gate_root || null;

    // P1 commercial: RID resolve with robust fallback
    if (!rid){
      try{
        const o = await fetchJSON("/api/vsp/rid_latest_gate_root");
        rid = pickRID(o);
      }catch(e1){
        // fallback: runs endpoint (GateStory already uses it; usually always available)
        try{
          const runs = await fetchJSON("/api/vsp/runs?limit=1&offset=0");
          const arr = Array.isArray(runs) ? runs : (runs.runs || runs.items || []);
          if (Array.isArray(arr) && arr.length){
            rid = pickRID(arr[0]);
          }
        }catch(e2){}
      }
    }

    if (!rid){
      mount.innerHTML="";
      mount.appendChild(el("div",{class:"vspP1Err"},[
        "Cannot resolve RID (rid_latest_gate_root + runs fallback)."
      ]));
      return;
    }
'''.strip("\n")

s2 = s[:m.start()] + new_block + s[m.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] patched RID resolve block with runs fallback")
PY

echo "[DONE] RID fallback applied."
echo "Next: restart UI then HARD refresh /vsp5."
