#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/test/Data/SECURITY_BUNDLE"
UI="$ROOT/ui"
VENV="$ROOT/.venv"
SERVICE="vsp-ui-8911-dev"

[ -x "$VENV/bin/gunicorn" ] || { echo "[ERR] missing gunicorn at $VENV/bin/gunicorn"; exit 1; }

UNIT="/etc/systemd/system/${SERVICE}.service"
sudo bash -c "cat > '$UNIT' <<'UNIT'
[Unit]
Description=VSP UI DEV (Gunicorn) on :8911
After=network.target

[Service]
Type=simple
User=$(id -un)
Group=$(id -gn)
WorkingDirectory=/home/test/Data/SECURITY_BUNDLE/ui
Environment=PYTHONUNBUFFERED=1
Environment=VSP_UI_MODE=DEV
ExecStart=/home/test/Data/SECURITY_BUNDLE/.venv/bin/gunicorn \
  -w 1 -k gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8911 \
  --access-logfile /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8911_access.log \
  --error-logfile  /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8911_error.log \
  wsgi_8910:application
Restart=always
RestartSec=1
KillSignal=SIGTERM
TimeoutStopSec=15

[Install]
WantedBy=multi-user.target
UNIT"

sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE}.service"
sudo systemctl restart "${SERVICE}.service"

echo "[OK] started ${SERVICE}"
sudo ss -ltnp | grep ":8911" || true
curl -sS -o /dev/null -w "HTTP=%{http_code}\n" http://127.0.0.1:8911/healthz || true
