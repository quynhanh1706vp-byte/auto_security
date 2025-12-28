#!/usr/bin/env bash
set -euo pipefail
UNIT="/etc/systemd/system/vsp-ui-8910.service"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need sudo; need systemctl; need sed; need grep; need date

sudo test -f "$UNIT" || { echo "[ERR] missing unit: $UNIT"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
sudo cp -f "$UNIT" "${UNIT}.bak_ready_${TS}"
echo "[BACKUP] ${UNIT}.bak_ready_${TS}"

# Ensure restart policy is sensible for demo stability
if sudo grep -q '^Restart=' "$UNIT"; then
  sudo sed -i 's/^Restart=.*/Restart=on-failure/' "$UNIT"
else
  sudo sed -i '/^\[Service\]/a Restart=on-failure' "$UNIT"
fi
if sudo grep -q '^RestartSec=' "$UNIT"; then
  sudo sed -i 's/^RestartSec=.*/RestartSec=1/' "$UNIT"
else
  sudo sed -i '/^\[Service\]/a RestartSec=1' "$UNIT"
fi

# Start/Stop timeouts (avoid stop-sigterm timeout -> SIGKILL loops)
if sudo grep -q '^TimeoutStartSec=' "$UNIT"; then
  sudo sed -i 's/^TimeoutStartSec=.*/TimeoutStartSec=30/' "$UNIT"
else
  sudo sed -i '/^\[Service\]/a TimeoutStartSec=30' "$UNIT"
fi
if sudo grep -q '^TimeoutStopSec=' "$UNIT"; then
  sudo sed -i 's/^TimeoutStopSec=.*/TimeoutStopSec=20/' "$UNIT"
else
  sudo sed -i '/^\[Service\]/a TimeoutStopSec=20' "$UNIT"
fi

# Readiness gate: only "Started" when /vsp5 is reachable
# Remove old ExecStartPost if exists, then insert ours
sudo sed -i '/^ExecStartPost=/d' "$UNIT"
sudo sed -i '/^\[Service\]/a ExecStartPost=/bin/bash -lc '"'"'for i in $(seq 1 60); do curl -fsS --connect-timeout 1 http://127.0.0.1:8910/vsp5 >/dev/null && exit 0; sleep 0.3; done; echo "[READY] /vsp5 not reachable" >&2; exit 1'"'"'' "$UNIT"

echo "[OK] patched readiness gate"

sudo systemctl daemon-reload
sudo systemctl restart vsp-ui-8910.service

echo "== status =="
sudo systemctl --no-pager -l status vsp-ui-8910.service | sed -n '1,35p'

echo "== curl smoke =="
curl -sS -I http://127.0.0.1:8910/vsp5 | head -n 8
curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | head -c 220; echo
