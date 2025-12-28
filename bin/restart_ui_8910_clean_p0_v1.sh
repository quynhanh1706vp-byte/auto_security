#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

PIDF="out_ci/ui_8910.pid"

echo "== stop 8910 =="
PID="$(cat "$PIDF" 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
pkill -f 'gunicorn .*--bind 127\.0\.0\.1:8910' 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.8

echo "== start 8910 =="
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid "$PIDF" \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.boot.log 2>&1 &

sleep 1.2
echo "== check listen =="
ss -ltnp | grep ':8910' || true
echo "== tail boot log =="
tail -n 30 out_ci/ui_8910.boot.log || true
