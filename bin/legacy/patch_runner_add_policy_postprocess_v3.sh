#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/test/Data/SECURITY_BUNDLE"
cd "$ROOT"

RUNNER="${1:-bin/run_all_tools_v2.sh}"
[ -f "$RUNNER" ] || { echo "[ERR] missing runner: $RUNNER"; exit 2; }

if grep -q "VSP_POLICY_POSTPROCESS_V3" "$RUNNER"; then
  echo "[OK] already patched: $RUNNER"
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$RUNNER" "$RUNNER.bak_policy_post_${TS}"
echo "[BACKUP] $RUNNER.bak_policy_post_${TS}"

python3 - "$RUNNER" <<'PY'
import sys, re
from pathlib import Path

runner = Path(sys.argv[1])
s = runner.read_text(encoding="utf-8", errors="ignore").splitlines(True)

block = r'''
# ===== [POLICY_POST] =====  # VSP_POLICY_POSTPROCESS_V3
echo "===== [POLICY_POST] policy_group + quality demote (commercial v2) ====="
python3 -u /home/test/Data/SECURITY_BUNDLE/bin/vsp_postprocess_policy_groups_v1.py "$RUN_DIR" || true
if [ -s "$RUN_DIR/findings_unified_commercial_v2.json" ]; then
  cp -f "$RUN_DIR/findings_unified_commercial_v2.json" "$RUN_DIR/findings_unified_current.json" || true
  echo "[POLICY_POST] wrote findings_unified_current.json (for UI)"
fi
'''

# Insert AFTER unify call (best-effort)
pat = re.compile(r'findings_unified_commercial\.json|vsp_unify_findings|unify_findings', re.I)
idx = None
for i, line in enumerate(s):
    if pat.search(line):
        idx = i + 1
        break
if idx is None:
    idx = len(s)

out = s[:idx] + [block if block.endswith("\n") else block + "\n"] + s[idx:]
runner.write_text("".join(out), encoding="utf-8")
print(f"[OK] inserted POLICY_POST at line~{idx+1} in {runner}")
PY

bash -n "$RUNNER"
echo "[OK] bash -n OK"
echo "[DONE] patched $RUNNER"
