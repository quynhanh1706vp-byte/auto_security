#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "[START] freeing :8910 ..."
PID="$(sudo ss -ltnp 2>/dev/null | awk '/:8910/ {print $NF}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | head -n1 || true)"
if [ -n "${PID:-}" ]; then
  echo "[START] kill pid=$PID"
  sudo kill -TERM "$PID" || true
  sleep 1
  sudo kill -KILL "$PID" || true
fi

pkill -f vsp_demo_app.py || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1
curl -sS -o /dev/null -w "HTTP=%{http_code}\n" http://localhost:8910/ || true
echo "[START] tail log:"
tail -n 40 out_ci/ui_8910.log | sed 's/\r/\n/g'
