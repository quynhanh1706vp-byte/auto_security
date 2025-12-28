#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

PIDF="out_ci/ui_8910.pid"
ERR="out_ci/ui_8910.error.log"
ACC="out_ci/ui_8910.access.log"

echo "== stop ALL 8910 =="
PID="$(cat "$PIDF" 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true

if command -v lsof >/dev/null 2>&1; then
  PIDS="$(lsof -tiTCP:8910 -sTCP:LISTEN 2>/dev/null || true)"
  [ -n "${PIDS:-}" ] && kill -KILL $PIDS 2>/dev/null || true
fi

rm -f "$PIDF" 2>/dev/null || true
sleep 0.8

echo "== start gunicorn (no restore) =="
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --max-requests 200 --max-requests-jitter 50 \

  --workers 1 --worker-class gthread --threads 2 --timeout 180 --graceful-timeout 30 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid "$PIDF" \
  --access-logfile "$ACC" --error-logfile "$ERR" \
  >/dev/null 2>&1 & disown || true

for i in 1 2 3 4 5 6 7 8; do
  curl -fsS http://127.0.0.1:8910/vsp4 >/dev/null 2>&1 && break
  sleep 1
done

ss -lntp | grep ':8910' || true
echo "[OK] http://127.0.0.1:8910/#dashboard"
