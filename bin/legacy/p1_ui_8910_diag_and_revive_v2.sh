#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need ss; need awk; need sed; need pkill; need nohup; need python3; need tail; need curl

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

echo "== (1) quick compile check =="
python3 -m py_compile "$F" && echo "[OK] py_compile OK"

echo "== (2) stop :8910 (best effort) =="
PIDS="$(ss -ltnp 2>/dev/null | awk '/127\.0\.0\.1:8910/ {print $NF}' | sed 's/.*pid=\([0-9]\+\).*/\1/' | tr '\n' ' ')"
if [ -n "${PIDS// /}" ]; then
  echo "[INFO] killing pids: ${PIDS}"
  for p in $PIDS; do kill "$p" 2>/dev/null || true; done
  sleep 0.6
fi
pkill -f "wsgi_vsp_ui_gateway:application" 2>/dev/null || true

mkdir -p out_ci

echo "== (3) start gunicorn :8910 =="
GUNI="./.venv/bin/gunicorn"
[ -x "$GUNI" ] || GUNI="$(command -v gunicorn || true)"
[ -n "${GUNI}" ] || { echo "[ERR] gunicorn not found"; exit 2; }

nohup "$GUNI" wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 \
  --timeout 60 --graceful-timeout 15 \
  --log-level info --capture-output \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui \
  --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 \
  --access-logfile out_ci/ui_8910.access.log \
  --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.boot.log 2>&1 &

echo "== (4) wait LISTEN =="
for i in 1 2 3 4 5 6 7 8 9 10; do
  if ss -ltnp 2>/dev/null | grep -q "127.0.0.1:8910"; then
    ss -ltnp | grep "127.0.0.1:8910" | sed 's/^/[OK] /' || true
    break
  fi
  sleep 0.4
done

echo "== (5) wait HTTP 200 / (stability) =="
OK=0
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if curl -fsSI --max-time 1.5 http://127.0.0.1:8910/ | head -n1 | grep -qi " 200 "; then
    echo "[OK] HTTP 200 /"
    OK=1
    break
  fi
  sleep 0.35
done

if [ "$OK" -ne 1 ]; then
  echo "[FAIL] HTTP not stable. Showing logs:"
  echo "----- out_ci/ui_8910.boot.log (tail) -----"
  tail -n 160 out_ci/ui_8910.boot.log 2>/dev/null || true
  echo "----- out_ci/ui_8910.error.log (tail) -----"
  tail -n 200 out_ci/ui_8910.error.log 2>/dev/null || true
  exit 4
fi

echo "[OK] 8910 is up + HTTP stable"
