#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/test/Data/SECURITY_BUNDLE"
UI="$ROOT/ui"
VENV="$ROOT/.venv"
SERVICE="vsp-ui-8911-dev"
UNIT="/etc/systemd/system/${SERVICE}.service"

U="$(id -un)"
G="$(id -gn)"

sudo bash -c "cat > '$UNIT' <<UNIT
[Unit]
Description=VSP UI DEV (Gunicorn) on :8911
After=network.target

[Service]
Type=simple
User=${U}
Group=${G}
WorkingDirectory=${UI}
Environment=PYTHONUNBUFFERED=1
Environment=VSP_UI_MODE=DEV

# ensure log dir exists
ExecStartPre=/usr/bin/mkdir -p ${UI}/out_ci

ExecStart=${VENV}/bin/gunicorn \\
  -w 1 -k gthread --threads 4 --timeout 60 --graceful-timeout 15 \\
  --chdir ${UI} --pythonpath ${UI} \\
  --bind 127.0.0.1:8911 \\
  --access-logfile ${UI}/out_ci/ui_8911_access.log \\
  --error-logfile  ${UI}/out_ci/ui_8911_error.log \\
  wsgi_8910:application

Restart=always
RestartSec=1
KillSignal=SIGTERM
TimeoutStopSec=15

[Install]
WantedBy=multi-user.target
UNIT"

sudo systemctl daemon-reload
sudo systemctl restart "${SERVICE}.service"

echo "== status top =="
sudo systemctl status "${SERVICE}.service" --no-pager | sed -n '1,35p' || true

echo "== listener =="
sudo ss -ltnp | grep ":8911" || true

echo "== healthz =="
curl -sS -o /dev/null -w "HTTP=%{http_code}\n" http://127.0.0.1:8911/healthz || true
curl -sS http://127.0.0.1:8911/healthz ; echo || true
