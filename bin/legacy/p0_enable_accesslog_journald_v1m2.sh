#!/usr/bin/env bash
set -euo pipefail

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need systemctl; need grep; need sed; need date

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

SVC="vsp-ui-8910.service"
DROP="/etc/systemd/system/${SVC}.d"

sudo mkdir -p "$DROP"

TS="$(date +%Y%m%d_%H%M%S)"
CONF="${DROP}/override_accesslog.conf"
if [ -f "$CONF" ]; then
  sudo cp -f "$CONF" "${CONF}.bak_${TS}"
  ok "backup: ${CONF}.bak_${TS}"
fi

cat > /tmp/override_accesslog.conf <<'CONF'
[Service]
# Ensure gunicorn access logs go to journald
Environment=GUNICORN_ACCESS_LOG=-
Environment=GUNICORN_ERROR_LOG=-
Environment=GUNICORN_LOG_LEVEL=info
CONF

sudo cp -f /tmp/override_accesslog.conf "$CONF"
ok "written: $CONF"

sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
ok "restarted: $SVC"

echo "== [DONE] Now reload /vsp5 and re-run the journalctl top endpoints command =="
