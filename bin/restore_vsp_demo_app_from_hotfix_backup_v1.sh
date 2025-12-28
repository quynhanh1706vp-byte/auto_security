#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"
BK="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py.bak_hotfix_run_status_500_v1_20251213_083256"

if [ ! -f "$BK" ]; then
  echo "[ERR] Backup không tồn tại: $BK"
  exit 1
fi

cp "$BK" "$APP"
echo "[OK] Restored: $APP <- $BK"

python3 -m py_compile "$APP" && echo "[OK] Python compile OK"
