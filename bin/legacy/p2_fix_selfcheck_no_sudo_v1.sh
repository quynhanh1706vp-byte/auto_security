#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p2_ui_state_selfcheck_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_nosudo_${TS}"
echo "[BACKUP] ${F}.bak_nosudo_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("bin/p2_ui_state_selfcheck_v1.sh")
s=p.read_text(encoding="utf-8", errors="replace")

# Replace any sudo journalctl usage with a safe block that skips if permission denied
s2=re.sub(
  r'(?s)say "Recent noisy logs.*?^\s*journalctl.*?$',
  'say "Recent noisy logs (BOOTFIX/READY_STUB/KPI_V4)"\n'
  'if journalctl -u "$SVC" --no-pager -n 220 >/dev/null 2>&1; then\n'
  '  journalctl -u "$SVC" --no-pager -n 220 | egrep -n "VSP_BOOTFIX|VSP_READY_STUB|VSP_KPI_V4" | tail -n 30 || true\n'
  'else\n'
  '  echo "[SKIP] journalctl not permitted (no sudo)";\n'
  'fi\n',
  s, flags=re.M
)

if s2==s:
  print("[WARN] could not locate journalctl block; no changes made")
else:
  p.write_text(s2, encoding="utf-8")
  print("[OK] patched: no-sudo journalctl")
PY

echo "[OK] run: bash bin/p2_ui_state_selfcheck_v1.sh"
