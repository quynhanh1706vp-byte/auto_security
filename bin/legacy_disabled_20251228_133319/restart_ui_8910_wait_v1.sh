#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

PID="$(cat out_ci/ui_8910.pid 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" || true
sleep 2

nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid out_ci/ui_8910.pid \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  >/dev/null 2>&1 &

# wait until ready
for i in $(seq 1 40); do
  if curl -fsS http://127.0.0.1:8910/vsp4 >/dev/null 2>&1; then
    echo "[OK] 8910 ready"
    exit 0
  fi
  sleep 0.2
done

echo "[ERR] 8910 not ready"
exit 1
