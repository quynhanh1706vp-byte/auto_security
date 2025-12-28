#!/usr/bin/env bash
set -euo pipefail

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need systemctl; need date

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

SVC="vsp-ui-8910.service"
DROP="/etc/systemd/system/${SVC}.d"
CONF="${DROP}/override_accesslog.conf"
TS="$(date +%Y%m%d_%H%M%S)"

sudo mkdir -p "$DROP"
if [ -f "$CONF" ]; then
  sudo cp -f "$CONF" "${CONF}.bak_${TS}"
  ok "backup: ${CONF}.bak_${TS}"
fi

cat > /tmp/override_accesslog.conf <<'CONF'
[Service]
# Force journald capture
StandardOutput=journal
StandardError=journal

# Force gunicorn to log access+error to stdout
Environment=GUNICORN_CMD_ARGS=--access-logfile - --error-logfile - --log-level info
CONF

sudo cp -f /tmp/override_accesslog.conf "$CONF"
ok "written: $CONF"

sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
ok "restarted: $SVC"

echo "== [CHECK] show last 40 lines of journal =="
sudo journalctl -u "$SVC" -n 40 --no-pager || true

echo "== [DONE] Now Ctrl+F5 /vsp5 then run the top-endpoints journalctl grep again =="
