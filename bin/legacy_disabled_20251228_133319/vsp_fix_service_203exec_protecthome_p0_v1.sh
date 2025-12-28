#!/usr/bin/env bash
set -euo pipefail

SVC="vsp-ui-8910.service"
UNIT="/etc/systemd/system/${SVC}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need sudo; need systemctl; need sed; need date

sudo test -f "$UNIT" || { echo "[ERR] missing unit: $UNIT"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
sudo cp -f "$UNIT" "${UNIT}.bak_203exec_${TS}"
echo "[BACKUP] ${UNIT}.bak_203exec_${TS}"

# Fix: allow /home so venv binaries can execute
if sudo grep -q '^ProtectHome=true' "$UNIT"; then
  sudo sed -i 's/^ProtectHome=true/ProtectHome=false/' "$UNIT"
  echo "[OK] ProtectHome: true -> false"
elif sudo grep -q '^ProtectHome=' "$UNIT"; then
  echo "[OK] ProtectHome already set (not true)"; 
else
  # if missing, add under [Service] for safety
  sudo sed -i '/^\[Service\]/a ProtectHome=false' "$UNIT"
  echo "[OK] ProtectHome inserted: false"
fi

echo "== daemon-reload + restart =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC" || true
sleep 1

echo "== status (short) =="
systemctl --no-pager --full status "$SVC" | sed -n '1,30p'

# If still failing, show useful logs
if ! systemctl is-active --quiet "$SVC"; then
  echo "== journal tail (last 120 lines) =="
  sudo journalctl -u "$SVC" -n 120 --no-pager
  exit 3
fi

echo "== smoke (5 tabs) =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_5tabs_smoke_p2_v1.sh

echo "[OK] service is ACTIVE + smoke PASS"
