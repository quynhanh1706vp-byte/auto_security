#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

S="bin/restart_8910_gunicorn_commercial_v5.sh"
[ -f "$S" ] || { echo "[ERR] missing $S"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$S" "$S.bak_gunicorn_runner_${TS}"
echo "[BACKUP] $S.bak_gunicorn_runner_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/restart_8910_gunicorn_commercial_v5.sh")
t = p.read_text(encoding="utf-8", errors="ignore")

# Inject runner selection near top (after set -euo pipefail)
inject = r'''
# gunicorn runner (commercial-safe)
GUNI_BIN=""
if [ -x "$ROOT/.venv/bin/gunicorn" ]; then
  GUNI_BIN="$ROOT/.venv/bin/gunicorn"
elif command -v gunicorn >/dev/null 2>&1; then
  GUNI_BIN="gunicorn"
else
  GUNI_BIN="python3 -m gunicorn"
fi
'''

if "GUNI_BIN" not in t:
    t = re.sub(r"(set -euo pipefail\s*\n)", r"\1\n"+inject+"\n", t, count=1)

# Replace "nohup gunicorn" with "nohup $GUNI_BIN"
t = re.sub(r"nohup\s+gunicorn\s+", "nohup $GUNI_BIN ", t)

p.write_text(t, encoding="utf-8")
print("[OK] patched to use $GUNI_BIN runner (venv/bin/gunicorn or python -m gunicorn)")
PY

chmod +x "$S"
grep -nE "GUNI_BIN|nohup" -n "$S" | head -n 40
