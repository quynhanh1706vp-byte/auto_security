#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE"
UI="$ROOT/ui"
VENV="$ROOT/.venv"
SVC="vsp-ui-gateway"
UNIT="/etc/systemd/system/${SVC}.service"

PORT="8910"
APP_WSGI="vsp_demo_app:app"   # Flask app object "app" trong vsp_demo_app.py
USER_NAME="test"
GROUP_NAME="test"

LOGDIR="$UI/out_ci/logs"
PIDFILE="/run/${SVC}.pid"

cd "$UI"

# 0) sanity
[ -d "$UI" ] || { echo "[ERR] missing UI dir: $UI"; exit 1; }
[ -x "$VENV/bin/python" ] || { echo "[ERR] missing venv python: $VENV/bin/python"; exit 1; }
[ -x "$VENV/bin/gunicorn" ] || { echo "[ERR] missing gunicorn in venv: $VENV/bin/gunicorn"; exit 1; }

mkdir -p "$LOGDIR"

# 1) backup unit nếu đã tồn tại
if sudo test -f "$UNIT"; then
  TS="$(date +%Y%m%d_%H%M%S)"
  sudo cp -f "$UNIT" "${UNIT}.bak_${TS}"
  echo "[BACKUP] ${UNIT}.bak_${TS}"
fi

# 2) write unit (KHÔNG đụng vsp-ui-8910.service)
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

# Runtime pid
PIDFile=${PIDFILE}
RuntimeDirectory=${SVC}
RuntimeDirectoryMode=0755

# Env (ưu tiên tools/bin để KICS/CodeQL nếu bạn bundle)
Environment=PYTHONUNBUFFERED=1
Environment=VSP_ROOT=${ROOT}
Environment=VSP_UI=${UI}
Environment=PATH=${ROOT}/tools/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Precheck nhanh (đừng để chết âm thầm)
ExecStartPre=/bin/bash -lc 'test -x "${VENV}/bin/gunicorn"'
ExecStartPre=/bin/bash -lc 'python -c "import importlib; importlib.import_module(\\"vsp_demo_app\\")"'

# Start gunicorn (log file nằm trong out_ci/logs để user test ghi được)
ExecStart=${VENV}/bin/gunicorn \\
  --bind 0.0.0.0:${PORT} \\
  --workers 2 \\
  --threads 4 \\
  --timeout 180 \\
  --access-logfile ${LOGDIR}/gunicorn_access.log \\
  --error-logfile ${LOGDIR}/gunicorn_error.log \\
  ${APP_WSGI}

Restart=on-failure
RestartSec=2
KillSignal=SIGTERM
TimeoutStopSec=20

# journald vẫn có (systemctl/journalctl), đồng thời gunicorn đã ghi file riêng
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo "[OK] wrote unit: $UNIT"

# 3) daemon-reload + enable + restart
sudo systemctl daemon-reload
sudo systemctl enable "$SVC"
sudo systemctl restart "$SVC"

# 4) verify
sleep 1
echo "== systemctl status =="
sudo systemctl --no-pager -l status "$SVC" || true

echo "== healthz =="
curl -sS -o /dev/null -w "HTTP=%{http_code}\n" "http://127.0.0.1:${PORT}/" || true

echo "== run_v1 {} =="
curl -sS -X POST "http://127.0.0.1:${PORT}/api/vsp/run_v1" -H 'Content-Type: application/json' -d '{}' | head -c 300; echo

echo "== listen :${PORT} =="
ss -lntp | awk 'NR==1 || /:'"${PORT}"'\b/'
echo "[DONE] service=${SVC}"
