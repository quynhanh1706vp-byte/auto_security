#!/usr/bin/env bash
set -euo pipefail

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need systemctl; need date; need sed; need grep; need curl; need ss

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

SVC="vsp-ui-8910.service"
DROP="/etc/systemd/system/${SVC}.d"
TS="$(date +%Y%m%d_%H%M%S)"
sudo mkdir -p "$DROP"

echo "== [1] List drop-ins BEFORE =="
sudo ls -la "$DROP" || true

echo "== [2] Disable ALL legacy accesslog overrides (match in DROP dir) =="
# Disable any file starting with override_accesslog and ending with .conf in DROP
for f in $(sudo bash -lc "ls -1 $DROP/override_accesslog*.conf 2>/dev/null || true"); do
  base="$(basename "$f")"
  sudo mv -f "$f" "$DROP/${base}.disabled_${TS}"
  ok "disabled: $base -> ${base}.disabled_${TS}"
done

echo "== [3] Write a SAFE journald override (no risky env parsing) =="
cat > /tmp/override_journald_v1m6.conf <<'CONF'
[Service]
StandardOutput=journal
StandardError=journal
Environment="PYTHONUNBUFFERED=1"
# Optional: only capture app stdout/stderr; do NOT add access/error logfile flags here
Environment="GUNICORN_CMD_ARGS=--capture-output"
CONF

sudo cp -f /tmp/override_journald_v1m6.conf "$DROP/override_journald_v1m6.conf"
ok "written: $DROP/override_journald_v1m6.conf"

echo "== [4] Reload + restart =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC" || true

echo "== [5] Wait up to 25s for 8910 to listen =="
for i in $(seq 1 50); do
  if ss -ltnp | grep -q ':8910'; then
    ok "port 8910 is LISTENING"
    break
  fi
  sleep 0.5
done

echo "== [6] Smoke curls (runs + api) =="
BASE="http://127.0.0.1:8910"
curl -fsS --connect-timeout 1 "$BASE/runs" >/dev/null && ok "/runs OK" || warn "/runs FAIL"
curl -fsS --connect-timeout 1 "$BASE/api/vsp/runs?limit=1" >/dev/null && ok "/api/vsp/runs OK" || warn "/api/vsp/runs FAIL"

echo "== [7] If still failing, show status + last logs =="
if ! ss -ltnp | grep -q ':8910'; then
  warn "8910 still not listening"
  sudo systemctl status "$SVC" --no-pager || true
  sudo journalctl -u "$SVC" -n 140 --no-pager -o cat || true
  err "recovery failed: 8910 not listening"
fi

echo "== [8] Drop-ins AFTER =="
sudo ls -la "$DROP" || true

echo "== [DONE] UI should be back at http://127.0.0.1:8910/vsp5 =="
