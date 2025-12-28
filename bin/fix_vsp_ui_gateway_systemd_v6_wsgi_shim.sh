#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE"
UI="$ROOT/ui"
VENV="$ROOT/.venv"
SVC="vsp-ui-gateway"
UNIT="/etc/systemd/system/${SVC}.service"
PORT="8910"

USER_NAME="test"
GROUP_NAME="test"

cd "$UI"

echo "== [0] stop + reset-failed =="
sudo systemctl stop "$SVC" 2>/dev/null || true
sudo systemctl reset-failed "$SVC" 2>/dev/null || true

echo "== [1] kill anything on :$PORT (sudo) =="
sudo fuser -k "${PORT}/tcp" 2>/dev/null || true
sleep 1
sudo fuser -k -9 "${PORT}/tcp" 2>/dev/null || true
sleep 1

echo "== [2] write WSGI shim (stable import) =="
cat > "$UI/wsgi_vsp_ui_gateway.py" <<'PY'
import importlib

m = importlib.import_module("vsp_demo_app")

if hasattr(m, "app"):
    application = m.app
elif hasattr(m, "create_app"):
    application = m.create_app()
else:
    raise RuntimeError("vsp_demo_app has no 'app' or 'create_app'")
PY

echo "== [3] write unit v6 (capture-output, wsgi shim) =="
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

Environment=PYTHONUNBUFFERED=1
Environment=VSP_ROOT=${ROOT}
Environment=VSP_UI=${UI}
Environment=PYTHONPATH=${UI}
Environment=PATH=${VENV}/bin:${ROOT}/tools/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Precheck: import shim (quote-safe)
ExecStartPre=/bin/bash -lc '${VENV}/bin/python -c '\''import wsgi_vsp_ui_gateway as w; assert callable(w.application)'\'''

ExecStart=${VENV}/bin/gunicorn \\
  --chdir ${UI} \\
  --bind 0.0.0.0:${PORT} \\
  --workers 2 \\
  --threads 4 \\
  --timeout 180 \\
  --log-level info \\
  --capture-output \\
  --access-logfile - \\
  --error-logfile - \\
  wsgi_vsp_ui_gateway:application

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

echo "== [4] status (must be active/running) =="
sudo systemctl --no-pager -l status "$SVC" || true

echo "== [5] journal last 160 (must show gunicorn bind / errors if any) =="
sudo journalctl -u "$SVC" -n 160 --no-pager || true

echo "== [6] verify listen (sudo ss + lsof) =="
sudo ss -lntp | awk 'NR==1 || /:'"${PORT}"'\b/' || true
sudo lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN 2>/dev/null || true

echo "== [7] curl local =="
curl -sS -o /dev/null -w "GET / => HTTP=%{http_code}\n" "http://127.0.0.1:${PORT}/" || true
curl -sS -X POST "http://127.0.0.1:${PORT}/api/vsp/run_v1" -H 'Content-Type: application/json' -d '{}' | head -c 260; echo

echo "[DONE] v6 applied"
