#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE

RUNNER="${1:-bin/run_all_tools_v2.sh}"
[ -f "$RUNNER" ] || { echo "[ERR] missing runner: $RUNNER"; exit 2; }

if grep -q "VSP_GATE_POLICY_STAGE_V1" "$RUNNER"; then
  echo "[OK] already patched: $RUNNER"
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$RUNNER" "$RUNNER.bak_gate_${TS}"
echo "[BACKUP] $RUNNER.bak_gate_${TS}"

python3 - "$RUNNER" <<'PY'
import sys, re
from pathlib import Path

runner = Path(sys.argv[1])
s = runner.read_text(encoding="utf-8", errors="ignore").splitlines(True)

block = r'''
# ===== [GATE_POLICY] =====  # VSP_GATE_POLICY_STAGE_V1
echo "===== [GATE_POLICY] commercial verdict (SECURITY-only + degraded) ====="
python3 -u /home/test/Data/SECURITY_BUNDLE/bin/vsp_gate_policy_commercial_v1.py "$RUN_DIR" || true
'''

# insert AFTER POLICY_POST block marker
pat = re.compile(r'VSP_POLICY_POSTPROCESS_V3', re.I)
idx = None
for i, line in enumerate(s):
    if pat.search(line):
        idx = i + 1
        break
if idx is None:
    idx = len(s)

out = s[:idx] + [block if block.endswith("\n") else block + "\n"] + s[idx:]
runner.write_text("".join(out), encoding="utf-8")
print(f"[OK] inserted GATE_POLICY at line~{idx+1} in {runner}")
PY

bash -n "$RUNNER"
echo "[OK] bash -n OK"
echo "[DONE] patched $RUNNER"
