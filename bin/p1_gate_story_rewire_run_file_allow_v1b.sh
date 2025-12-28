#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
CAND="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$CAND" ] || { echo "[ERR] missing $CAND"; exit 2; }

cp -f "$CAND" "${CAND}.bak_gate_rewire_${TS}"
echo "[BACKUP] ${CAND}.bak_gate_rewire_${TS}"

python3 - "$CAND" <<'PY'
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_GATE_STORY_REWIRE_RUN_FILE_ALLOW_V1B"
if marker in s:
    print("[OK] already patched:", p)
    raise SystemExit(0)

s2, n1 = re.subn(r"/api/vsp/run_file\b", "/api/vsp/run_file_allow", s)
s2, n2 = re.subn(r"api/vsp/run_file\?", "api/vsp/run_file_allow?", s2)

addon = f"\n/* {marker} */\nconsole.log('[GateStoryV1] rewire: run_file -> run_file_allow');\n"
p.write_text(s2 + addon, encoding="utf-8")

print("[OK] patched:", p)
print("[OK] replacements:", n1 + n2)
PY

sudo systemctl restart vsp-ui-8910.service >/dev/null 2>&1 || true
echo "[DONE] HARD refresh /vsp5 (Ctrl+Shift+R). Look for console: rewire: run_file -> run_file_allow"
