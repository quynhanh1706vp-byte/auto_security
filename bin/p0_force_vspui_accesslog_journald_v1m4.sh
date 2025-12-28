#!/usr/bin/env bash
set -euo pipefail

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need systemctl; need date; need grep; need sed; need curl

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

SVC="vsp-ui-8910.service"
DROP="/etc/systemd/system/${SVC}.d"
TS="$(date +%Y%m%d_%H%M%S)"
CONF="${DROP}/override_accesslog_v1m4.conf"

sudo mkdir -p "$DROP"

if [ -f "$CONF" ]; then
  sudo cp -f "$CONF" "${CONF}.bak_${TS}"
  ok "backup: ${CONF}.bak_${TS}"
fi

cat > /tmp/override_accesslog_v1m4.conf <<'CONF'
[Service]
# Make sure stdout/stderr go to journald
StandardOutput=journal
StandardError=journal

# Force gunicorn to emit access+error logs to stdout and capture app output
Environment=PYTHONUNBUFFERED=1
Environment=GUNICORN_CMD_ARGS=--access-logfile - --error-logfile - --log-level info --capture-output
CONF

sudo cp -f /tmp/override_accesslog_v1m4.conf "$CONF"
ok "written: $CONF"

sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
ok "restarted: $SVC"

echo "== [CHECK] last 60 lines (should include gunicorn startup) =="
sudo journalctl -u "$SVC" -n 60 --no-pager -o cat || true

# Generate a few requests to force access logs
BASE="http://127.0.0.1:8910"
curl -fsS "$BASE/api/vsp/runs?limit=1" >/dev/null || true
curl -fsS "$BASE/api/vsp/release_latest" >/dev/null || true
curl -fsS "$BASE/api/vsp/rid_latest" >/dev/null || true

echo "== [CHECK] last 40 lines after curls (should include GET /api/vsp/...) =="
sudo journalctl -u "$SVC" -n 40 --no-pager -o cat || true

echo "== [TOP] endpoints in last 25s =="
sudo journalctl -u "$SVC" --since "25 seconds ago" --no-pager -o cat \
| egrep 'GET /api/vsp/' \
| sed -E 's/.*GET (\/api\/vsp\/[^ ]+).*/\1/' \
| sed -E 's/[?&]ts=[0-9]+//g' \
| sort | uniq -c | sort -nr | head -n 25 || true

