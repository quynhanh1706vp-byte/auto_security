#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== find pids binding 8910 =="
PIDS="$(ps -ef | grep -E "gunicorn" | grep -E "127\.0\.0\.1:8910" | grep -v grep | awk '{print $2}' | tr '\n' ' ')"
echo "PIDS=$PIDS"

if [ -n "${PIDS// /}" ]; then
  echo "== kill 8910 gunicorn =="
  for p in $PIDS; do kill -9 "$p" 2>/dev/null || true; done
  sleep 1
fi

echo "== start gunicorn 8910 (vsp_demo_app:app) =="
mkdir -p out_ci
nohup python3 -m gunicorn -w 1 -b 127.0.0.1:8910 --log-level info \
  --access-logfile out_ci/ui_8910_access.log \
  --error-logfile  out_ci/ui_8910_error.log \
  vsp_demo_app:app > out_ci/ui_8910_nohup.log 2>&1 &

sleep 1
echo "== health check =="
curl -sS -o /dev/null -w "HTTP=%{http_code}\n" http://127.0.0.1:8910/
echo "[OK] restarted 8910"
