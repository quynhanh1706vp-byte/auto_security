#!/usr/bin/env bash
set -euo pipefail

UNIT="/etc/systemd/system/vsp-ui-8910.service"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need sudo; need systemctl; need sed; need grep; need date

sudo test -f "$UNIT" || { echo "[ERR] missing unit: $UNIT"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
sudo cp -f "$UNIT" "${UNIT}.bak_stopfix_${TS}"
echo "[BACKUP] ${UNIT}.bak_stopfix_${TS}"

# Ensure [Service] has robust stop semantics (fix stop-sigterm timeout -> SIGKILL loops)
# 1) Add/replace TimeoutStopSec
if sudo grep -q '^TimeoutStopSec=' "$UNIT"; then
  sudo sed -i 's/^TimeoutStopSec=.*/TimeoutStopSec=20/' "$UNIT"
else
  sudo sed -i '/^\[Service\]/a TimeoutStopSec=20' "$UNIT"
fi

# 2) KillMode=mixed (TERM main, then workers)
if sudo grep -q '^KillMode=' "$UNIT"; then
  sudo sed -i 's/^KillMode=.*/KillMode=mixed/' "$UNIT"
else
  sudo sed -i '/^\[Service\]/a KillMode=mixed' "$UNIT"
fi

# 3) Consider SIGTERM normal exit for gunicorn
if sudo grep -q '^SuccessExitStatus=' "$UNIT"; then
  sudo sed -i 's/^SuccessExitStatus=.*/SuccessExitStatus=143/' "$UNIT"
else
  sudo sed -i '/^\[Service\]/a SuccessExitStatus=143' "$UNIT"
fi

# 4) PIDFile so systemd tracks the right master
PIDFILE="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.pid"
if sudo grep -q '^PIDFile=' "$UNIT"; then
  sudo sed -i "s|^PIDFile=.*|PIDFile=${PIDFILE}|" "$UNIT"
else
  sudo sed -i "/^\[Service\]/a PIDFile=${PIDFILE}" "$UNIT"
fi

# 5) Ensure ExecStart has --pid (so PIDFile is real)
# (Best-effort: only add if not present)
if ! sudo grep -q -- '--pid' "$UNIT"; then
  sudo sed -i 's/--bind 127\.0\.0\.1:8910/--bind 127.0.0.1:8910 --pid out_ci\/ui_8910.pid/' "$UNIT" || true
fi

# 6) Make stop explicit (TERM mainpid), then systemd handles rest by itself
if sudo grep -q '^ExecStop=' "$UNIT"; then
  sudo sed -i 's|^ExecStop=.*|ExecStop=/bin/kill -TERM $MAINPID|' "$UNIT"
else
  sudo sed -i '/^\[Service\]/a ExecStop=/bin/kill -TERM $MAINPID' "$UNIT"
fi

echo "[OK] patched unit stop semantics"

sudo systemctl daemon-reload
sudo systemctl restart vsp-ui-8910.service

echo "== status (short) =="
sudo systemctl --no-pager -l status vsp-ui-8910.service | sed -n '1,22p'

echo "== quick curl =="
curl -sS -I http://127.0.0.1:8910/vsp5 | head -n 8
curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | head -c 220; echo

echo "[DONE] From now on: only use systemctl restart/stop; avoid nohup gunicorn for 8910."
