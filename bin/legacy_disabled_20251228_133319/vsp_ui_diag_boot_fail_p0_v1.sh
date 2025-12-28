#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
mkdir -p out_ci
TS="$(date +%Y%m%d_%H%M%S)"
BOOT="out_ci/ui_8910.boot.log"
ERR="out_ci/ui_8910.error.log"

echo "== stop 8910 =="
PID="$(cat out_ci/ui_8910.pid 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.6
fuser -k 8910/tcp 2>/dev/null || true
sleep 0.4

echo "== quick py_compile (top-level) =="
/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python -m py_compile \
  vsp_demo_app.py wsgi_vsp_ui_gateway.py 2>/dev/null && echo "[OK] py_compile core OK" || echo "[WARN] py_compile core FAILED"

echo "== start gunicorn (capture boot log) =="
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 \
  --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid out_ci/ui_8910.pid \
  --access-logfile out_ci/ui_8910.access.log --error-logfile "$ERR" \
  >"$BOOT" 2>&1 &

sleep 0.8

echo "== listen? =="
if ss -lntp | grep -q ':8910'; then
  ss -lntp | grep ':8910' || true
  echo "[OK] UI is up"
  exit 0
fi

echo "[FAIL] 8910 not listening (gunicorn likely exited 1)"
echo "---- boot log tail ----"
tail -n 200 "$BOOT" 2>/dev/null || true
echo "---- error log tail ----"
tail -n 200 "$ERR" 2>/dev/null || true

echo "== grep Traceback/ImportError/SyntaxError =="
grep -nE "Traceback|ImportError|ModuleNotFoundError|SyntaxError|Error:" "$BOOT" | tail -n 80 || true

echo "== full py_compile sweep (find .py) =="
find . -maxdepth 4 -type f -name "*.py" -print0 \
| xargs -0 -n 80 /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python -m py_compile \
|| echo "[WARN] some py_compile failed (see above)"

exit 2
