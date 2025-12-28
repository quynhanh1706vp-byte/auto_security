#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

PID_FILE="out_ci/ui_8910.pid"
ERR_LOG="out_ci/ui_8910.error.log"
ACC_LOG="out_ci/ui_8910.access.log"

mkdir -p out_ci

echo "== stop =="
PID="$(cat "$PID_FILE" 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.8

echo "== start =="
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid "$PID_FILE" \
  --access-logfile "$ACC_LOG" --error-logfile "$ERR_LOG" \
  >/dev/null 2>&1 &

sleep 0.8

echo "== check process =="
PID2="$(cat "$PID_FILE" 2>/dev/null || true)"
if [ -z "${PID2:-}" ] || ! ps -p "$PID2" >/dev/null 2>&1; then
  echo "[FAIL] gunicorn not running (pid=$PID2)"
  echo "== last error log =="
  tail -n 160 "$ERR_LOG" 2>/dev/null || echo "[NOLOG] $ERR_LOG missing/empty"
  exit 2
fi
echo "[OK] pid=$PID2 alive"

echo "== check listen 8910 =="
if ss -ltnp 2>/dev/null | grep -q ':8910'; then
  ss -ltnp | grep ':8910' || true
  echo "[OK] listening"
else
  echo "[FAIL] not listening on 8910"
  echo "== last error log =="
  tail -n 160 "$ERR_LOG" 2>/dev/null || echo "[NOLOG] $ERR_LOG missing/empty"
  exit 3
fi

echo "== quick curl =="
curl -sS -m 2 http://127.0.0.1:8910/health 2>/dev/null || true
curl -sS -m 2 http://127.0.0.1:8910/vsp4 >/dev/null && echo "[OK] /vsp4 OK" || echo "[WARN] /vsp4 not OK yet"

echo "[DONE] UI up."
