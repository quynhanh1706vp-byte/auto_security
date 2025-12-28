#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need ss; need awk; need sed; need sort; need head; need tail; need curl; need python3; need date
mkdir -p out_ci

echo "== cleanup lock/pid =="
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.pid out_ci/ui_8910.pid 2>/dev/null || true

echo "== kill listeners on :8910 =="
pids="$(ss -ltnp | awk '/:8910/ {print $0}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u)"
if [ -n "${pids:-}" ]; then
  echo "[INFO] killing pids: $pids"
  kill -9 $pids 2>/dev/null || true
fi

echo "== quick import check =="
python3 - <<'PY'
import sys
try:
  import wsgi_vsp_ui_gateway
  print("[OK] import wsgi_vsp_ui_gateway OK")
except Exception as e:
  print("[ERR] import failed:", e)
  raise
PY

echo "== truncate logs =="
: > out_ci/ui_8910.boot.log || true
: > out_ci/ui_8910.error.log || true
: > out_ci/ui_8910.access.log || true
: > out_ci/ui_8910.diag.log || true

GUNICORN="./.venv/bin/gunicorn"
APP="wsgi_vsp_ui_gateway:application"
ARGS=(--workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log)

echo "== DIAG run (6s) to catch crash reason =="
if command -v timeout >/dev/null 2>&1; then
  timeout 6s "$GUNICORN" $APP "${ARGS[@]}" > out_ci/ui_8910.diag.log 2>&1 || true
else
  "$GUNICORN" $APP "${ARGS[@]}" > out_ci/ui_8910.diag.log 2>&1 || true
fi
echo "== diag highlights =="
grep -nE "Listening at|Traceback|ERROR|Exception|SyntaxError|ImportError|ModuleNotFoundError|Address already in use" out_ci/ui_8910.diag.log | tail -n 80 || true
echo "== diag tail =="
tail -n 80 out_ci/ui_8910.diag.log || true

echo "== start background =="
nohup "$GUNICORN" $APP "${ARGS[@]}" > out_ci/ui_8910.boot.log 2>&1 &
echo $! > out_ci/ui_8910.pid
sleep 0.8

echo "== probe =="
for u in / /vsp5 "/api/vsp/runs?limit=1"; do
  code="$(curl -sS -o /tmp/_p.json -w '%{http_code}' "http://127.0.0.1:8910${u}" || true)"
  echo "[PROBE] ${u} => ${code}"
done

echo "== ss :8910 =="
ss -ltnp | egrep '(:8910)\b' || true

echo "== boot tail =="
tail -n 120 out_ci/ui_8910.boot.log || true
