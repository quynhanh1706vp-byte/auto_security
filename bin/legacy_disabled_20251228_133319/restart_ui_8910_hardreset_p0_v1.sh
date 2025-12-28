#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

PIDF="out_ci/ui_8910.pid"

echo "== HARD RESET 8910 =="

PID=""
if [ -f "$PIDF" ]; then
  PID="$(cat "$PIDF" 2>/dev/null || true)"
  echo "[PIDFILE] $PIDF => ${PID:-EMPTY}"
fi

# kill pid from pidfile
if [ -n "${PID:-}" ]; then
  echo "== kill PID from pidfile =="
  kill -TERM "$PID" 2>/dev/null || true
  sleep 0.6
  kill -KILL "$PID" 2>/dev/null || true
fi

# kill any gunicorn bound to 8910
echo "== pkill gunicorn 8910 =="
pkill -f 'gunicorn .*--bind 127\.0\.0\.1:8910' 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.6

# remove stale pidfile if still exists
echo "== remove stale pidfile =="
rm -f "$PIDF" || true

bash /home/test/Data/SECURITY_BUNDLE/ui/bin/ui_prestart_guard_clean_py_p0_v1.sh >/dev/null

echo "== start 8910 =="
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid "$PIDF" \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.boot.log 2>&1 &

sleep 1.0
echo "== check listen =="
ss -ltnp | grep ':8910' || true
echo "== boot log tail =="
tail -n 40 out_ci/ui_8910.boot.log || true
