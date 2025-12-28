#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE"
UI="$ROOT/ui"
VENV="$ROOT/.venv"
SVC="vsp-ui-gateway"
UNIT="/etc/systemd/system/${SVC}.service"
PORT="8910"

APP_WSGI="vsp_demo_app:app"
USER_NAME="test"
GROUP_NAME="test"

LOGDIR="$UI/out_ci/logs"
RUNDIR="/run/${SVC}"
PIDFILE="${RUNDIR}/gunicorn.pid"

cd "$UI"
mkdir -p "$LOGDIR"

echo "== [0] stop restart storm (if any) =="
sudo systemctl reset-failed "$SVC" 2>/dev/null || true
sudo systemctl stop "$SVC" 2>/dev/null || true

echo "== [1] who owns :$PORT (sudo) =="
sudo ss -lntp | awk 'NR==1 || /:'"${PORT}"'\b/' || true
sudo fuser -v "${PORT}/tcp" 2>/dev/null || true

echo "== [2] kill any listeners on :$PORT (sudo) =="
sudo fuser -k "${PORT}/tcp" 2>/dev/null || true
sleep 1
sudo fuser -k -9 "${PORT}/tcp" 2>/dev/null || true
sleep 1

echo "== [3] rewrite unit (v3) - fix python -c quoting + PATH includes venv =="
TS="$(date +%Y%m%d_%H%M%S)"
if sudo test -f "$UNIT"; then
  sudo cp -f "$UNIT" "${UNIT}.bak_${TS}"
  echo "[BACKUP] ${UNIT}.bak_${TS}"
fi

sudo tee "$UNIT" >/dev/null <<EOF
[Unit]
Description=VSP UI Gateway (Commercial) on :${PORT}
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=${USER_NAME}
Group=${GROUP_NAME}
WorkingDirectory=${UI}

RuntimeDirectory=${SVC}
RuntimeDirectoryMode=0755

Environment=PYTHONUNBUFFERED=1
Environment=VSP_ROOT=${ROOT}
Environment=VSP_UI=${UI}
Environment=PATH=${VENV}/bin:${ROOT}/tools/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Precheck: absolute venv python, quote-safe
ExecStartPre=/bin/bash -lc '${VENV}/bin/python -c '\''import importlib; importlib.import_module("vsp_demo_app")'\'''
ExecStartPre=/bin/bash -lc 'test -x ${VENV}/bin/gunicorn'

ExecStart=${VENV}/bin/gunicorn \\
  --bind 0.0.0.0:${PORT} \\
  --workers 2 \\
  --threads 4 \\
  --timeout 180 \\
  --pid ${PIDFILE} \\
  --access-logfile ${LOGDIR}/gunicorn_access.log \\
  --error-logfile ${LOGDIR}/gunicorn_error.log \\
  ${APP_WSGI}

Restart=on-failure
RestartSec=2
KillSignal=SIGTERM
TimeoutStopSec=20
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$SVC"
sudo systemctl restart "$SVC" || true

echo "== [4] status + journal (last 120) =="
sudo systemctl --no-pager -l status "$SVC" || true
sudo journalctl -u "$SVC" -n 120 --no-pager || true

echo "== [5] verify owner :$PORT (sudo) =="
sudo ss -lntp | awk 'NR==1 || /:'"${PORT}"'\b/' || true

echo "== [6] HTTP verify =="
curl -sS -o /dev/null -w "GET / => HTTP=%{http_code}\n" "http://127.0.0.1:${PORT}/" || true
curl -sS -X POST "http://127.0.0.1:${PORT}/api/vsp/run_v1" -H 'Content-Type: application/json' -d '{}' | head -c 300; echo

echo "[DONE] systemd v3 applied"
