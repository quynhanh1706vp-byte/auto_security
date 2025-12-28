#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/test/Data/SECURITY_BUNDLE"
RUNNER="$ROOT/bin/run_security_bundle_real.sh"
HOOK_MARK="ENSURE_MIN_REPORTS_V2_HOOKED_V2"

[ -f "$RUNNER" ] || { echo "[ERR] missing runner: $RUNNER"; exit 2; }

if grep -q "$HOOK_MARK" "$RUNNER"; then
  echo "[OK] already hooked: $RUNNER ($HOOK_MARK)"
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$RUNNER" "${RUNNER}.bak_hook_${TS}"
echo "[BACKUP] ${RUNNER}.bak_hook_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

runner = Path("/home/test/Data/SECURITY_BUNDLE/bin/run_security_bundle_real.sh")
s = runner.read_text(encoding="utf-8", errors="replace")

MARK = "ENSURE_MIN_REPORTS_V2_HOOKED_V2"
hook = r'''
# ENSURE_MIN_REPORTS_V2_HOOKED_V2
if [ -n "${RUN_DIR:-}" ] && [ -d "${RUN_DIR:-}" ]; then
  python3 /home/test/Data/SECURITY_BUNDLE/bin/ensure_min_reports_v2.py "${RUN_DIR}" || true
fi
'''.strip() + "\n"

if MARK in s:
    print("[OK] already present"); raise SystemExit(0)

# Try to insert right after unify invocation if found; otherwise append to end.
pat = re.compile(r'^(.*(?:unify\.sh|vsp_unify|unify_findings|findings_unified).*)$', re.M)
m = pat.search(s)

if m:
    end = m.end()
    s = s[:end] + "\n" + hook + s[end:]
else:
    s = s.rstrip() + "\n\n" + hook

runner.write_text(s, encoding="utf-8")
print("[OK] hooked:", runner)
PY

bash -n "$RUNNER" && echo "[OK] bash -n OK: $RUNNER"

echo "[DONE] Now run a fresh scan; new RUN should always have reports/{index.html,run_gate_summary.json,findings_unified.json,SUMMARY.txt}"
