#!/usr/bin/env bash
set -euo pipefail
UNIT="/etc/systemd/system/vsp-ui-8910.service"
[ -f "$UNIT" ] || { echo "[ERR] missing $UNIT"; exit 1; }

sudo cp -f "$UNIT" "${UNIT}.bak_$(date +%Y%m%d_%H%M%S)"
echo "[BACKUP] ${UNIT}.bak_*"

sudo python3 - <<'PY'
from pathlib import Path
u = Path("/etc/systemd/system/vsp-ui-8910.service")
txt = u.read_text(encoding="utf-8", errors="ignore")

# Make ExecStart more robust (force chdir + pythonpath)
txt = txt.replace(
"ExecStart=/home/test/Data/SECURITY_BUNDLE/.venv/bin/gunicorn",
"ExecStart=/home/test/Data/SECURITY_BUNDLE/.venv/bin/gunicorn --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui"
)

u.write_text(txt, encoding="utf-8")
print("[OK] patched ExecStart with --chdir/--pythonpath")
PY

sudo systemctl daemon-reload
sudo systemctl restart vsp-ui-8910
sudo ss -ltnp | grep ":8910" || true
curl -sS -o /dev/null -w "HTTP=%{http_code}\n" http://127.0.0.1:8910/healthz || true
