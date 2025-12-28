#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

PID="$(cat out_ci/ui_8910.pid 2>/dev/null || true)"
if [ -n "${PID:-}" ]; then
  kill -TERM "$PID" || true
  sleep 2
fi

nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid out_ci/ui_8910.pid \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  >/dev/null 2>&1 &

sleep 1
curl -sS -D- http://127.0.0.1:8910/healthz -o /dev/null | head -n 5 || true
echo "[OK] restarted"
