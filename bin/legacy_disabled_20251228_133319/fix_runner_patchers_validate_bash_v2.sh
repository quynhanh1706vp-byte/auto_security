#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

mapfile -t TARGETS < <(grep -RIl 'python3 -m py_compile "\$RUNNER"' bin/patch_runner_* 2>/dev/null || true)

if [ "${#TARGETS[@]}" -eq 0 ]; then
  echo "[OK] no patch_runner_* needs fix (py_compile on RUNNER not found)"
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
for f in "${TARGETS[@]}"; do
  [ -f "$f" ] || continue
  cp -f "$f" "$f.bak_validate_${TS}"
  echo "[BACKUP] $f.bak_validate_${TS}"

  python3 - "$f" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="ignore")

s = s.replace('python3 -m py_compile "$RUNNER"', 'bash -n "$RUNNER"')
s = s.replace('echo "[OK] py_compile OK"', 'echo "[OK] bash -n OK"')

p.write_text(s, encoding="utf-8")
print("[OK] patched", p)
PY

  bash -n "$f"
done

echo "[DONE] fixed validation for: ${#TARGETS[@]} scripts"
