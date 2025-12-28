#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need ss; need awk; need sed; need pkill; need nohup; need python3; need tail; need curl

PORT=8910
ADDR="127.0.0.1:${PORT}"
F="wsgi_vsp_ui_gateway.py"

echo "== (0) compile check =="
python3 -m py_compile "$F" && echo "[OK] py_compile OK"

echo "== (1) stop systemd unit if exists (best effort) =="
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-units --type=service --all 2>/dev/null | grep -q "vsp-ui-8910.service"; then
    echo "[INFO] systemd unit exists: vsp-ui-8910.service"
    sudo -n systemctl stop vsp-ui-8910.service 2>/dev/null || true
    sudo -n systemctl disable vsp-ui-8910.service 2>/dev/null || true
  fi
fi

echo "== (2) kill all listeners on :8910 =="
PIDS="$(ss -ltnp 2>/dev/null | awk "/${ADDR}/ {print \$NF}" | sed 's/.*pid=\\([0-9]\\+\\).*/\\1/' | tr '\n' ' ')"
if [ -n "${PIDS// /}" ]; then
  echo "[INFO] killing pids: ${PIDS}"
  for p in $PIDS; do kill "$p" 2>/dev/null || true; done
  sleep 0.6
  for p in $PIDS; do kill -9 "$p" 2>/dev/null || true; done
fi
pkill -9 -f "wsgi_vsp_ui_gateway:application" 2>/dev/null || true
pkill -9 -f "gunicorn.*${PORT}" 2>/dev/null || true

echo "== (3) wait port free =="
for i in 1 2 3 4 5 6 7 8 9 10; do
  if ss -ltnp 2>/dev/null | grep -q "${ADDR}"; then
    sleep 0.3
  else
    echo "[OK] port free"
    break
  fi
done

mkdir -p out_ci

echo "== (4) start single gunicorn :8910 =="
GUNI="./.venv/bin/gunicorn"
[ -x "$GUNI" ] || GUNI="$(command -v gunicorn || true)"
[ -n "${GUNI}" ] || { echo "[ERR] gunicorn not found"; exit 2; }

nohup "$GUNI" wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 \
  --timeout 60 --graceful-timeout 15 \
  --log-level info --capture-output \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui \
  --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:${PORT} \
  --access-logfile out_ci/ui_8910.access.log \
  --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.boot.log 2>&1 &

echo "== (5) wait HTTP 200 / and /vsp5 =="
ok=0
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if curl -fsSI --max-time 2 "http://127.0.0.1:${PORT}/" | head -n1 | grep -qi " 200 " \
  && curl -fsSI --max-time 2 "http://127.0.0.1:${PORT}/vsp5" | head -n1 | grep -qi " 200 "; then
    echo "[OK] HTTP stable: / and /vsp5"
    ok=1
    break
  fi
  sleep 0.35
done

if [ "$ok" -ne 1 ]; then
  echo "[FAIL] HTTP not stable. Logs:"
  echo "----- boot.log (tail) -----"
  tail -n 120 out_ci/ui_8910.boot.log 2>/dev/null || true
  echo "----- error.log (tail) -----"
  tail -n 200 out_ci/ui_8910.error.log 2>/dev/null || true
  exit 4
fi

echo "[DONE] 8910 single-owner up"
