#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== KILL =="
PID="$(cat out_ci/ui_8910.pid 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
sleep 0.4
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.4

echo "== IMPORT CHECK (most common crash cause) =="
# show python exception immediately if import fails
/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python - <<'PY'
import traceback
try:
    import wsgi_vsp_ui_gateway
    print("[OK] import wsgi_vsp_ui_gateway")
except Exception as e:
    print("[ERR] import failed:", e)
    traceback.print_exc()
    raise
PY

echo "== START 8910 (capture-output) =="
: > out_ci/ui_8910.nohup.log
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid out_ci/ui_8910.pid \
  --log-level debug --capture-output \
  --access-logfile - --error-logfile - > out_ci/ui_8910.nohup.log 2>&1 &

sleep 0.6
echo "== LISTEN CHECK =="
if ss -ltnp | grep -q ':8910'; then
  ss -ltnp | grep ':8910' || true
  echo "[OK] 8910 listening"
else
  echo "[ERR] 8910 NOT listening"
  echo "== LAST LOG =="
  tail -n 200 out_ci/ui_8910.nohup.log || true
  exit 1
fi

echo "== SMOKE =="
curl -fsS http://127.0.0.1:8910/vsp4 >/dev/null && echo "[OK] /vsp4 HTTP OK" || {
  echo "[ERR] /vsp4 not ok"
  tail -n 200 out_ci/ui_8910.nohup.log || true
  exit 2
}
