#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

pkill -f vsp_demo_app.py || true
rm -f out_ci/ui_8910.log || true
mkdir -p out_ci

nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1

echo "[OK] UI started. PID(s):"
pgrep -af vsp_demo_app.py || true
echo
echo "=== Last log ==="
tail -n 30 out_ci/ui_8910.log || true
