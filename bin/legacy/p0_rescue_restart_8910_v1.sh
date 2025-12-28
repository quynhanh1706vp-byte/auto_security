#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

PID_FILE="out_ci/ui_8910.pid"
echo "== stop =="
PID="$(cat "$PID_FILE" 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.8

echo "== start =="
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid "$PID_FILE" \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.nohup.log 2>&1 &

echo "== wait =="
for i in 1 2 3 4 5; do
  if curl -fsS http://127.0.0.1:8910/vsp4 >/dev/null 2>&1; then
    echo "[OK] UI up: /vsp4"
    ss -ltnp | grep ':8910' || true
    exit 0
  fi
  sleep 0.6
done

echo "[ERR] 8910 still down. Logs:"
tail -n 120 out_ci/ui_8910.nohup.log || true
tail -n 120 out_ci/ui_8910.error.log || true
exit 1
