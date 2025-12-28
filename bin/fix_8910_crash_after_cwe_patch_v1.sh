#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== stop =="
PID="$(cat out_ci/ui_8910.pid 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.6

echo "== show last error log (before restore) =="
tail -n 120 out_ci/ui_8910.error.log 2>/dev/null || true

echo "== restore wsgi from latest bak_cwe_enrich (rollback crashing patch) =="
BAK="$(ls -1t wsgi_vsp_ui_gateway.py.bak_cwe_enrich_* 2>/dev/null | head -n1 || true)"
if [ -z "${BAK:-}" ]; then
  echo "[ERR] no backup wsgi_vsp_ui_gateway.py.bak_cwe_enrich_* found"
  exit 2
fi
cp -f "$BAK" wsgi_vsp_ui_gateway.py
echo "[OK] restored => $BAK"

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"

echo "== start =="
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid out_ci/ui_8910.pid \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  >/dev/null 2>&1 &
sleep 0.8

echo "== probe =="
curl -sS -o /dev/null -w "HTTP=%{http_code}\n" http://127.0.0.1:8910/vsp4 || true

echo "== last error log (after start) =="
tail -n 80 out_ci/ui_8910.error.log 2>/dev/null || true
