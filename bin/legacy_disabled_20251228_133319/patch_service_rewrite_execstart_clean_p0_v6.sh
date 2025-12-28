#!/usr/bin/env bash
set -euo pipefail

SVC="vsp-ui-8910.service"
UNIT="/etc/systemd/system/${SVC}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need sudo; need systemctl; need ss; need date; need install; need awk; need sed; need grep; need curl

sudo test -f "$UNIT" || { echo "[ERR] missing unit: $UNIT"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
sudo cp -f "$UNIT" "${UNIT}.bak_rewrite_execstart_${TS}"
echo "[BACKUP] ${UNIT}.bak_rewrite_execstart_${TS}"

TMP="/tmp/${SVC}.rewrite_${TS}"
cat > "$TMP" <<'UNITF'
[Unit]
Description=VSP UI Gateway (commercial) :8910
After=network.target

[Service]
Type=simple
User=test
Group=test
WorkingDirectory=/home/test/Data/SECURITY_BUNDLE/ui
Environment=PYTHONUNBUFFERED=1
Environment=PYTHONDONTWRITEBYTECODE=1

# VSP_PORT_GUARD_8910_P0_V6 (systemd-native, no escaping tricks)
ExecStartPre=-/usr/sbin/fuser -k 8910/tcp
ExecStartPre=-/usr/bin/pkill -f "gunicorn .*8910"
ExecStartPre=-/usr/bin/sleep 0.2

# IMPORTANT: ExecStart must be a SINGLE LINE in systemd unit (no '\' line continuation)
ExecStart=/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui --bind 127.0.0.1:8910 --access-logfile /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.access.log --error-logfile /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log

Restart=on-failure
RestartSec=1
TimeoutStartSec=30
TimeoutStopSec=8
KillMode=mixed
LimitNOFILE=65535
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=false
ReadWritePaths=/home/test/Data/SECURITY_BUNDLE/ui/out_ci

[Install]
WantedBy=multi-user.target
UNITF

echo "== install unit (sudo) =="
sudo install -m 0644 "$TMP" "$UNIT"

echo "== daemon-reload =="
sudo systemctl daemon-reload

echo "== reset failed + restart =="
sudo systemctl reset-failed "$SVC" || true
sudo systemctl restart "$SVC" || true

echo "== status =="
sudo systemctl --no-pager --full status "$SVC" | sed -n '1,120p' || true

echo "== journal tail =="
sudo journalctl -u "$SVC" -n 120 --no-pager || true

echo "== ss listen :8910 =="
ss -ltnp | grep -E ':8910\b' || { echo "[FAIL] still not listening"; exit 3; }

echo "== curl =="
curl -m 2 -sS -I http://127.0.0.1:8910/ | sed -n '1,20p' || { echo "[FAIL] curl failed"; exit 4; }

echo "[OK] service stable + port 8910 listening"
