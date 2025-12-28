#!/usr/bin/env bash
set -euo pipefail

UI_DIR="/home/test/Data/SECURITY_BUNDLE/ui"
USER_RUN="test"
GROUP_RUN="test"
PORT="8910"
BIND="127.0.0.1:${PORT}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need sudo; need systemctl

[ -d "$UI_DIR" ] || { echo "[ERR] missing UI_DIR=$UI_DIR"; exit 2; }
[ -x "$UI_DIR/.venv/bin/gunicorn" ] || { echo "[ERR] missing gunicorn venv: $UI_DIR/.venv/bin/gunicorn"; exit 2; }

echo "== INSTALL systemd: vsp-ui-8910.service =="
sudo tee /etc/systemd/system/vsp-ui-8910.service >/dev/null <<EOF
[Unit]
Description=VSP UI Gateway (commercial) :8910
After=network.target

[Service]
Type=simple
User=${USER_RUN}
Group=${GROUP_RUN}
WorkingDirectory=${UI_DIR}
Environment=PYTHONUNBUFFERED=1
Environment=PYTHONDONTWRITEBYTECODE=1

ExecStart=${UI_DIR}/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \\
  --workers 2 --worker-class gthread --threads 4 \\
  --timeout 60 --graceful-timeout 15 \\
  --chdir ${UI_DIR} --pythonpath ${UI_DIR} \\
  --bind ${BIND} \\
  --access-logfile ${UI_DIR}/out_ci/ui_8910.access.log \\
  --error-logfile ${UI_DIR}/out_ci/ui_8910.error.log

Restart=always
RestartSec=1
TimeoutStartSec=30
TimeoutStopSec=15
LimitNOFILE=65535
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=${UI_DIR}/out_ci

[Install]
WantedBy=multi-user.target
EOF

echo "== INSTALL logrotate =="
sudo tee /etc/logrotate.d/vsp-ui-8910 >/dev/null <<EOF
${UI_DIR}/out_ci/ui_8910.access.log
${UI_DIR}/out_ci/ui_8910.error.log
${UI_DIR}/out_ci/ui_8910.boot.log
{
  daily
  rotate 14
  missingok
  notifempty
  compress
  delaycompress
  copytruncate
}
EOF

echo "== ENABLE + RESTART service =="
sudo systemctl daemon-reload
sudo systemctl enable vsp-ui-8910.service
sudo systemctl restart vsp-ui-8910.service
sleep 1

echo "== STATUS (short) =="
systemctl --no-pager --full status vsp-ui-8910.service | sed -n '1,25p'

echo "== SMOKE (5 tabs) =="
bash ${UI_DIR}/bin/vsp_ui_5tabs_smoke_p2_v1.sh

echo "[OK] commercial service installed & smoke PASS"
echo "[NEXT] UI: http://127.0.0.1:${PORT}/vsp4 (Ctrl+Shift+R)"
