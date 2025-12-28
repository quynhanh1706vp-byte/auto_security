#!/usr/bin/env bash
set -euo pipefail

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need systemctl; need date; need ls; need sed; need grep; need curl

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

SVC="vsp-ui-8910.service"
DROP="/etc/systemd/system/${SVC}.d"
TS="$(date +%Y%m%d_%H%M%S)"

sudo mkdir -p "$DROP"

echo "== [1] Disable old accesslog overrides (if any) =="
for f in override_accesslog*.conf; do
  if sudo test -f "$DROP/$f"; then
    sudo mv -f "$DROP/$f" "$DROP/${f}.disabled_${TS}"
    ok "disabled: $DROP/$f -> ${f}.disabled_${TS}"
  fi
done

echo "== [2] Write NEW fixed override (quoted env) =="
cat > /tmp/override_accesslog_v1m5.conf <<'CONF'
[Service]
StandardOutput=journal
StandardError=journal
Environment="PYTHONUNBUFFERED=1"
Environment="GUNICORN_CMD_ARGS=--access-logfile - --error-logfile - --log-level info --capture-output"
CONF

sudo cp -f /tmp/override_accesslog_v1m5.conf "$DROP/override_accesslog_v1m5.conf"
ok "written: $DROP/override_accesslog_v1m5.conf"

echo "== [3] Reload + restart =="
sudo systemctl daemon-reload

if sudo systemctl restart "$SVC"; then
  ok "restarted: $SVC"
else
  warn "restart FAILED. Showing status + journal tail:"
  sudo systemctl status "$SVC" --no-pager || true
  sudo journalctl -xeu "$SVC" -n 120 --no-pager || true
  err "service still failing (see logs above)"
fi

echo "== [4] Quick smoke curls to generate access log lines =="
BASE="http://127.0.0.1:8910"
curl -fsS "$BASE/api/vsp/runs?limit=1" >/dev/null || true
curl -fsS "$BASE/api/vsp/release_latest" >/dev/null || true
curl -fsS "$BASE/api/vsp/rid_latest" >/dev/null || true

echo "== [5] Last 60 journal lines (should include GET /api/vsp/...) =="
sudo journalctl -u "$SVC" -n 60 --no-pager -o cat || true

echo "== [DONE] Now reload /vsp5 and run your top-endpoints grep =="
