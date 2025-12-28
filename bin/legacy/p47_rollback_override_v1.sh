#!/usr/bin/env bash
set -euo pipefail
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need date; need ls; need cp

TS="$(date +%Y%m%d_%H%M%S)"
OVDIR="/etc/systemd/system/${SVC}.d"
OVCONF="${OVDIR}/override.conf"

echo "== [P47-ROLLBACK] $SVC =="

if sudo test -f "$OVCONF"; then
  sudo cp -f "$OVCONF" "${OVCONF}.bak_rollback_${TS}"
  echo "[BACKUP] ${OVCONF}.bak_rollback_${TS}"
  sudo rm -f "$OVCONF"
  echo "[OK] removed $OVCONF"
else
  echo "[OK] no override.conf to remove"
fi

sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"

echo "== quick check =="
curl -sS -o /dev/null -w "vsp5 http_code=%{http_code} time_total=%{time_total}\n" --connect-timeout 2 --max-time 5 "http://127.0.0.1:8910/vsp5" || true
