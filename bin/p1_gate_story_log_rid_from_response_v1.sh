#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

F="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_rid_from_resp_${TS}"
echo "[BACKUP] ${F}.bak_rid_from_resp_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_dashboard_gate_story_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P1_GATE_STORY_RID_FROM_RESPONSE_V1"
if marker in s:
    print("[SKIP] already patched")
    raise SystemExit(0)

# Heuristic: after JSON parse success, inject rid overwrite
# Insert near first occurrence of ".run_id" usage or after "gate =" assignment.
ins = r"""
/* VSP_P1_GATE_STORY_RID_FROM_RESPONSE_V1 */
try{
  if (gate && gate.run_id && typeof gate.run_id === "string" && gate.run_id.trim()){
    rid = gate.run_id.trim();
    try{ window.vsp_rid_latest = rid; }catch(e){}
  }
}catch(e){}
"""

# place after a line that looks like "var gate = ..." or "gate = ..."
m = re.search(r'\b(gate\s*=\s*JSON\.parse\([^;]*\)\s*;)', s)
if m:
    idx = m.end()
    s = s[:idx] + "\n" + ins + "\n" + s[idx:]
else:
    # fallback: prepend (still safe)
    s = ins + "\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] patched:", marker)
PY

echo "[OK] done. Ctrl+F5 /vsp5"
