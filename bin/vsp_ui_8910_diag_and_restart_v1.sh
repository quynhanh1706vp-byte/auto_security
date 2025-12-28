#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== (0) stop 8910 hard =="
PIDF="out_ci/ui_8910.pid"
PID="$(cat "$PIDF" 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
pkill -f 'gunicorn .*127\.0\.0\.1:8910' 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.8

echo "== (1) start 8910 clean =="
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

echo "== (2) wait listen <=6s =="
for i in 1 2 3 4 5 6; do
  ss -ltnp | grep -q ':8910' && break || true
  sleep 1
done

echo "== (3) ss listen =="
ss -ltnp | grep ':8910' || { echo "[FAIL] 8910 not listening"; tail -n 120 out_ci/ui_8910.boot.log; exit 2; }

echo "== (4) curl smoke =="
curl -sS -I http://127.0.0.1:8910/vsp5 | head -n 8
curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | head -c 220; echo

echo "== (5) last logs =="
echo "-- boot.log (tail 40) --"
tail -n 40 out_ci/ui_8910.boot.log || true
echo "-- error.log (tail 40) --"
tail -n 40 out_ci/ui_8910.error.log || true

echo "[OK] Now open /vsp5 and Ctrl+F5. Console should stop REFUSED."
