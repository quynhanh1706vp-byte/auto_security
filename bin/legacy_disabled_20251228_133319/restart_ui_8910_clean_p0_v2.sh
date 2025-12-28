#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

PIDF="out_ci/ui_8910.pid"

echo "== stop by pidfile =="
if [ -f "$PIDF" ]; then
  PID="$(cat "$PIDF" 2>/dev/null || true)"
  if [ -n "${PID:-}" ]; then
    kill -TERM "$PID" 2>/dev/null || true
    sleep 0.8
    kill -KILL "$PID" 2>/dev/null || true
  fi
fi

echo "== stop by pkill =="
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.8
pkill -9 -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.5

echo "== cleanup stale pidfile =="
rm -f "$PIDF" 2>/dev/null || true

echo "== start =="
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid "$PIDF" \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.boot.log 2>&1 &

echo "== wait listen =="
ok=0
for i in 1 2 3 4 5 6; do
  if ss -ltnp 2>/dev/null | grep -q ':8910'; then ok=1; break; fi
  sleep 1
done
[ "$ok" = "1" ] || { echo "[FAIL] not listening"; tail -n 80 out_ci/ui_8910.error.log || true; exit 2; }

ss -ltnp | grep ':8910' || true
curl -sS -I http://127.0.0.1:8910/vsp4 | head
