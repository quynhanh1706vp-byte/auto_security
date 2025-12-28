#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

PIDF="out_ci/ui_8910.pid"
ERR="out_ci/ui_8910.error.log"
ACC="out_ci/ui_8910.access.log"

echo "== (0) stop ALL 8910 (pidfile + pgrep + lsof) =="
PID="$(cat "$PIDF" 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true

# kill anything still LISTEN on 8910 (hard)
if command -v lsof >/dev/null 2>&1; then
  PIDS="$(lsof -tiTCP:8910 -sTCP:LISTEN 2>/dev/null || true)"
  if [ -n "${PIDS:-}" ]; then
    echo "[WARN] force kill LISTEN pids: $PIDS"
    kill -KILL $PIDS 2>/dev/null || true
  fi
fi

rm -f "$PIDF" 2>/dev/null || true
sleep 0.8

echo "== (1) restore SAFE snapshot if exists =="
if [ -x bin/vsp_restore_ui_snapshot_latest_v1.sh ] && [ -f out_ci/snapshots/ui_safe_latest.tgz ]; then
  bash bin/vsp_restore_ui_snapshot_latest_v1.sh
else
  echo "[WARN] SAFE snapshot not found; skip restore"
fi

echo "== (2) start gunicorn (single source of truth: nohup) =="
mkdir -p out_ci
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 120 --graceful-timeout 30 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid "$PIDF" \
  --access-logfile "$ACC" --error-logfile "$ERR" \
  >/dev/null 2>&1 & disown || true

echo "== (3) wait up to 8s for /vsp4 =="
OK=0
for i in 1 2 3 4 5 6 7 8; do
  if curl -fsS http://127.0.0.1:8910/vsp4 >/dev/null 2>&1; then OK=1; break; fi
  sleep 1
done

echo "== (4) status =="
ss -lntp | grep ':8910' || true
pgrep -af 'gunicorn .*8910' || true

if [ "$OK" = "1" ]; then
  echo "[OK] UI is up: http://127.0.0.1:8910/#dashboard"
  exit 0
fi

echo "[ERR] UI still down. Last error log:"
tail -n 120 "$ERR" || true
exit 2
