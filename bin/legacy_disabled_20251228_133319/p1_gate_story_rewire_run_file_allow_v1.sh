#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"

# find GateStory JS (loaded on /vsp5)
CAND="$(grep -RIn --exclude='*.bak_*' -m1 "GateStoryV1B" static/js 2>/dev/null | cut -d: -f1 || true)"
if [ -z "$CAND" ]; then
  CAND="$(ls -1 static/js/*gate*story*.js 2>/dev/null | head -n1 || true)"
fi
[ -n "$CAND" ] || { echo "[ERR] cannot locate GateStory JS under static/js"; exit 2; }

echo "[INFO] target JS: $CAND"
cp -f "$CAND" "${CAND}.bak_gate_rewire_${TS}"
echo "[BACKUP] ${CAND}.bak_gate_rewire_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_GATE_STORY_REWIRE_RUN_FILE_ALLOW_V1"
if marker in s:
    print("[OK] already patched:", p)
    raise SystemExit(0)

# 1) replace API path
s2, n = re.subn(r"/api/vsp/run_file\b", "/api/vsp/run_file_allow", s)

# 2) also replace any literal "run_file?rid=" URL fragments if present
s2, n2 = re.subn(r"api/vsp/run_file\?", "api/vsp/run_file_allow?", s2)

# 3) add marker + small console note
addon = "\n/* "+marker+" */\nconsole.log('[GateStoryV1B] rewire: run_file -> run_file_allow');\n"
p.write_text(s2 + addon, encoding="utf-8")

print("[OK] patched:", p)
print("[OK] replacements:", n + n2)
PY "$CAND"

echo
echo "[DONE] Now HARD refresh /vsp5: Ctrl+Shift+R"
echo "       You should no longer see 'not available' and Run overall should become real."
