#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== kill existing gunicorn 8910 (owned by current user) =="
ps -ef | grep -E "gunicorn.*--bind 0\.0\.0\.0:8910" | grep -v grep || true
PIDS="$(ps -ef | grep -E "gunicorn.*--bind 0\.0\.0\.0:8910" | grep -v grep | awk '{print $2}' || true)"

if [ -n "${PIDS:-}" ]; then
  echo "$PIDS" | xargs -r kill -TERM || true
  sleep 1
  echo "$PIDS" | xargs -r kill -KILL || true
fi

rm -f out_ci/ui_8910.lock out_ci/ui_8910.pid 2>/dev/null || true

echo "== start gunicorn 8910 (wsgi_vsp_ui_gateway:application) =="
nohup /home/test/Data/SECURITY_BUNDLE/.venv/bin/gunicorn \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 0.0.0.0:8910 \
  --workers 2 \
  --threads 4 \
  --timeout 180 \
  --log-level info \
  --capture-output \
  --access-logfile - \
  --error-logfile - \
  wsgi_vsp_ui_gateway:application \
  > out_ci/gunicorn_8910.log 2>&1 &

sleep 1
echo "== verify healthz =="
curl -sS -D- "http://127.0.0.1:8910/healthz" -o /dev/null | head -n 20 || true
echo "[OK] log: out_ci/gunicorn_8910.log"
