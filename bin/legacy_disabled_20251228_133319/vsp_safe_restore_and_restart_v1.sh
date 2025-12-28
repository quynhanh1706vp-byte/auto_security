#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TPL="templates/vsp_dashboard_2025.html"
PIDF="out_ci/ui_8910.pid"
ERR="out_ci/ui_8910.error.log"
ACC="out_ci/ui_8910.access.log"

mkdir -p out_ci

echo "== find SAFE backup containing VSP_SAFE_APP_ENTRY =="
SAFE=""
for f in $(ls -1t templates/vsp_dashboard_2025.html.bak_safe_* 2>/dev/null || true); do
  if grep -q "VSP_SAFE_APP_ENTRY" "$f"; then SAFE="$f"; break; fi
done
echo "[SAFE]=${SAFE:-<none>}"
[ -n "${SAFE:-}" ] || { echo "[ERR] no SAFE backup found (missing marker VSP_SAFE_APP_ENTRY)"; exit 2; }

cp -f "$SAFE" "$TPL"
echo "[OK] restored template => $TPL"

echo "== stop by PID (no pkill) =="
if [ -f "$PIDF" ]; then
  PID="$(cat "$PIDF" 2>/dev/null || true)"
  if [ -n "${PID:-}" ] && kill -0 "$PID" 2>/dev/null; then
    echo "[STOP] kill -TERM $PID"
    kill -TERM "$PID" 2>/dev/null || true
    for i in $(seq 1 30); do
      kill -0 "$PID" 2>/dev/null || break
      sleep 0.2
    done
    kill -0 "$PID" 2>/dev/null && { echo "[STOP] still alive -> kill -KILL $PID"; kill -KILL "$PID" 2>/dev/null || true; }
  else
    echo "[STOP] PID file exists but process not running"
  fi
fi

echo "== start gunicorn (detached) =="
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid "$PIDF" \
  --access-logfile "$ACC" --error-logfile "$ERR" \
  >/dev/null 2>&1 & disown || true

sleep 0.5
echo "== check =="
ss -ltnp | grep ':8910' || { echo "[ERR] 8910 not listening. Tail error log:"; tail -n 80 "$ERR" || true; exit 3; }
curl -sS -m 2 http://127.0.0.1:8910/vsp4 >/dev/null && echo "[OK] /vsp4 reachable" || { echo "[WARN] /vsp4 not reachable yet"; tail -n 80 "$ERR" || true; }
echo "[DONE] SAFE restore + restart OK"
