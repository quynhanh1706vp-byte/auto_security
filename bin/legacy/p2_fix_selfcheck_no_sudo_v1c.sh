#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p2_ui_state_selfcheck_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_nosudo_v1c_${TS}"
echo "[BACKUP] ${F}.bak_nosudo_v1c_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("bin/p2_ui_state_selfcheck_v1.sh")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

start = None
end = None

# find the "Recent noisy logs" section start
for i, ln in enumerate(lines):
    if 'say "Recent noisy logs' in ln:
        start = i
        break

if start is None:
    print("[WARN] could not find 'Recent noisy logs' section; no changes made")
    raise SystemExit(0)

# end at next "say " header after start, or EOF
for j in range(start + 1, len(lines)):
    if lines[j].lstrip().startswith('say "'):
        end = j
        break
if end is None:
    end = len(lines)

safe_block = [
    'say "Recent noisy logs (BOOTFIX/READY_STUB/KPI_V4)"\n',
    'if journalctl -u "$SVC" -n 220 --no-pager >/dev/null 2>&1; then\n',
    '  journalctl -u "$SVC" -n 220 --no-pager | egrep -n "VSP_BOOTFIX|VSP_READY_STUB|VSP_KPI_V4" | tail -n 30 || true\n',
    'else\n',
    '  echo "[SKIP] journalctl not permitted (no sudo)"\n',
    'fi\n',
]

new_lines = lines[:start] + safe_block + lines[end:]
p.write_text("".join(new_lines), encoding="utf-8")
print(f"[OK] replaced log block lines {start+1}..{end} with safe nosudo block")
PY

echo
echo "== SHELLCHECK (bash -n) =="
bash -n "$F" && echo "[OK] bash -n passed"

echo
echo "== RUN selfcheck (tail) =="
bash "$F" | tail -n 60
