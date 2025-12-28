#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

if systemctl --user list-unit-files | grep -q '^vsp-ui-8910\.service'; then
  echo "[RESTART] systemd --user vsp-ui-8910.service"
  systemctl --user restart vsp-ui-8910.service
  sleep 1
else
  echo "[RESTART] pkill + nohup (no systemd user unit found)"
  pkill -f vsp_demo_app.py || true
  nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
  sleep 1
fi

echo "== healthz =="
curl -sS http://127.0.0.1:8910/healthz; echo
echo "== version =="
curl -sS http://127.0.0.1:8910/api/vsp/version; echo
