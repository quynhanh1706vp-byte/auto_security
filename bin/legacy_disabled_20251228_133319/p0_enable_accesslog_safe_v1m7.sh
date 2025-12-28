#!/usr/bin/env bash
set -euo pipefail

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need systemctl; need date; need curl; need ss

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

SVC="vsp-ui-8910.service"
DROP="/etc/systemd/system/${SVC}.d"
TS="$(date +%Y%m%d_%H%M%S)"
CONF="${DROP}/override_accesslog_safe_v1m7.conf"

sudo mkdir -p "$DROP"

if sudo test -f "$CONF"; then
  sudo cp -f "$CONF" "${CONF}.bak_${TS}"
  ok "backup: ${CONF}.bak_${TS}"
fi

cat > /tmp/override_accesslog_safe_v1m7.conf <<'CONF'
[Service]
StandardOutput=journal
StandardError=journal
Environment="PYTHONUNBUFFERED=1"
# Enable access+error logs to stdout (journald) + capture app output
Environment="GUNICORN_CMD_ARGS=--access-logfile - --error-logfile - --log-level info --capture-output"
CONF

sudo cp -f /tmp/override_accesslog_safe_v1m7.conf "$CONF"
ok "written: $CONF"

sudo systemctl daemon-reload
sudo systemctl restart "$SVC"

# wait a bit
for i in $(seq 1 30); do
  ss -ltnp | grep -q ':8910' && break
  sleep 0.3
done
ss -ltnp | grep -q ':8910' || err "8910 not listening after restart"

BASE="http://127.0.0.1:8910"
curl -fsS "$BASE/api/vsp/runs?limit=1" >/dev/null || true
curl -fsS "$BASE/api/vsp/rid_latest" >/dev/null || true
curl -fsS "$BASE/api/vsp/release_latest" >/dev/null || true

echo "== [CHECK] last 60 lines (should include \"GET /api/vsp/\") =="
sudo journalctl -u "$SVC" -n 60 --no-pager -o cat || true

echo "== [DONE] Now reload /vsp5 then run the top-endpoints command =="
