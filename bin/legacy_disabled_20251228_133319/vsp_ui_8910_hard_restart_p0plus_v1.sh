#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== stop anything on 8910 =="
PIDF="out_ci/ui_8910.pid"
PID="$(cat "$PIDF" 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
pkill -f 'gunicorn .*127\.0\.0\.1:8910' 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.8

echo "== start clean gunicorn 8910 =="
mkdir -p out_ci
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn \
  wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 \
  --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui \
  --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 \
  --pid out_ci/ui_8910.pid \
  --access-logfile out_ci/ui_8910.access.log \
  --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.boot.log 2>&1 &

echo "== wait listen (<=6s) =="
for i in 1 2 3 4 5 6; do
  ss -ltnp | grep -q ':8910' && break || true
  sleep 1
done

echo "== verify =="
ss -ltnp | grep ':8910' || { echo "[FAIL] 8910 not listening"; tail -n 120 out_ci/ui_8910.boot.log; exit 2; }

echo "-- curl / (head) --"
curl -sS -I http://127.0.0.1:8910/ | head -n 12 || true

echo "-- curl runs API --"
curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | head -c 300; echo

echo "[OK] backend reachable. Now Ctrl+F5 on /vsp5"
