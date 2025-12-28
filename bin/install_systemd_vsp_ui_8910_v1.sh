#!/usr/bin/env bash
set -euo pipefail

UI_DIR="/home/test/Data/SECURITY_BUNDLE/ui"
VENV="$UI_DIR/.venv"
GUNICORN="$VENV/bin/gunicorn"

[ -d "$UI_DIR" ] || { echo "[ERR] missing $UI_DIR"; exit 1; }
[ -x "$GUNICORN" ] || { echo "[ERR] missing gunicorn at $GUNICORN (install in ui/.venv)"; exit 2; }

# Best-guess app entry
APP="vsp_demo_app:app"

sudo bash -lc "cat > /etc/systemd/system/vsp-ui-8910.service" <<EOF
[Unit]
Description=VSP UI Gateway (8910)
After=network.target

[Service]
Type=simple
WorkingDirectory=$UI_DIR
Environment=PYTHONUNBUFFERED=1
Environment=VSP_STATUS_STALL_SEC=900
ExecStart=$GUNICORN --workers 2 --threads 4 --timeout 180 --bind 0.0.0.0:8910 $APP
Restart=always
RestartSec=2
KillSignal=SIGTERM
TimeoutStopSec=30

# Logs via journald (recommended)
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo "[OK] wrote /etc/systemd/system/vsp-ui-8910.service (APP=$APP)"

sudo systemctl daemon-reload
sudo systemctl enable vsp-ui-8910.service
sudo systemctl restart vsp-ui-8910.service
sudo systemctl --no-pager --full status vsp-ui-8910.service | sed -n '1,25p'

echo "[OK] You can view logs: sudo journalctl -u vsp-ui-8910 -f"
