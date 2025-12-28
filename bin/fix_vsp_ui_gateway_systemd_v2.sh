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

echo "== [A] show who owns :$PORT (before) =="
ss -lntp | awk 'NR==1 || /:'"${PORT}"'\b/'

echo "== [B] stop service if exists =="
sudo systemctl stop "$SVC" 2>/dev/null || true

echo "== [C] kill any leftover listeners on :$PORT (commercial-hard) =="
PIDS="$(ss -lntp 2>/dev/null | awk '/:'"${PORT}"'\b/ {print $NF}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u || true)"
if [ -n "${PIDS:-}" ]; then
  echo "[INFO] killing pids on :$PORT => $PIDS"
  for p in $PIDS; do
    sudo kill -TERM "$p" 2>/dev/null || true
  done
  sleep 1
  for p in $PIDS; do
    sudo kill -KILL "$p" 2>/dev/null || true
  done
fi

echo "== [D] rewrite unit (v2) with absolute paths (NO \${VENV}) =="
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

[Service]
Type=simple
User=${USER_NAME}
Group=${GROUP_NAME}
WorkingDirectory=${UI}

# systemd will create /run/vsp-ui-gateway owned by User/Group
RuntimeDirectory=${SVC}
RuntimeDirectoryMode=0755

Environment=PYTHONUNBUFFERED=1
Environment=VSP_ROOT=${ROOT}
Environment=VSP_UI=${UI}
Environment=PATH=${ROOT}/tools/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Precheck: venv + import
ExecStartPre=/bin/bash -lc 'test -x ${VENV}/bin/gunicorn'
ExecStartPre=/bin/bash -lc '${VENV}/bin/python -c "import importlib; importlib.import_module(\\"vsp_demo_app\\")"'

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

echo "== [E] status + last logs =="
sudo systemctl --no-pager -l status "$SVC" || true
echo "--- journal (last 120 lines) ---"
sudo journalctl -u "$SVC" -n 120 --no-pager || true

echo "== [F] quick HTTP verify =="
sleep 1
curl -sS -o /dev/null -w "GET / => HTTP=%{http_code}\n" "http://127.0.0.1:${PORT}/" || true
curl -sS -X POST "http://127.0.0.1:${PORT}/api/vsp/run_v1" -H 'Content-Type: application/json' -d '{}' | head -c 300; echo

echo "== [G] who owns :$PORT (after) =="
ss -lntp | awk 'NR==1 || /:'"${PORT}"'\b/'
echo "[DONE] fix_v2 applied"
