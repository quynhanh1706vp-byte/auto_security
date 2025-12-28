#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need ss; need awk; need pkill; need nohup

GUNI="./.venv/bin/gunicorn"
[ -x "$GUNI" ] || GUNI="$(command -v gunicorn || true)"
[ -n "${GUNI}" ] || { echo "[ERR] gunicorn not found"; exit 2; }

echo "== stop :8910 =="
PIDS="$(ss -ltnp 2>/dev/null | awk '/127\.0\.0\.1:8910/ {print $NF}' | sed 's/.*pid=\([0-9]\+\).*/\1/' | tr '\n' ' ')"
if [ -n "${PIDS// /}" ]; then
  echo "[INFO] killing pids: ${PIDS}"
  for p in $PIDS; do kill "$p" 2>/dev/null || true; done
  sleep 0.6
fi
pkill -f "wsgi_vsp_ui_gateway:application" 2>/dev/null || true

mkdir -p out_ci

echo "== start gunicorn :8910 =="
nohup "$GUNI" wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 \
  --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui \
  --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 \
  --access-logfile out_ci/ui_8910.access.log \
  --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.boot.log 2>&1 &

sleep 0.8
ss -ltnp | awk '/127\.0\.0\.1:8910/ {print "[OK] listening:", $0}' || true
echo "[OK] restart done; Ctrl+F5"
