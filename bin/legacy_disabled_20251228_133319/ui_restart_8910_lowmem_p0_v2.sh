#!/usr/bin/env bash
set -u
cd /home/test/Data/SECURITY_BUNDLE/ui || exit 2

PIDF="out_ci/ui_8910.pid"
ERR="out_ci/ui_8910.error.log"
ACC="out_ci/ui_8910.access.log"
mkdir -p out_ci

echo "== stop ALL 8910 =="
PID="$(cat "$PIDF" 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.8

echo "== mem snapshot (optional) =="
free -h 2>/dev/null || echo "[WARN] free not available"

echo "== start gunicorn LOW-MEM =="
export MALLOC_ARENA_MAX=2
export PYTHONUNBUFFERED=1

nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 1 \
  --worker-class gthread --threads 6 \
  --timeout 180 --graceful-timeout 30 --keep-alive 5 \
  --max-requests 120 --max-requests-jitter 30 \
  --worker-tmp-dir /dev/shm \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid "$PIDF" \
  --access-logfile "$ACC" --error-logfile "$ERR" \
  >/dev/null 2>&1 & disown || true

echo "== wait up to 6s for listen =="
OK=0
for i in 1 2 3 4 5 6; do
  if command -v ss >/dev/null 2>&1; then
    ss -lntp 2>/dev/null | grep -q ':8910' && OK=1 && break
  else
    # fallback: try curl
    curl -fsS http://127.0.0.1:8910/vsp4 >/dev/null 2>&1 && OK=1 && break
  fi
  sleep 1
done

echo "== status =="
if command -v ss >/dev/null 2>&1; then ss -lntp 2>/dev/null | grep ':8910' || echo "DOWN:not listening"; fi
pgrep -af 'gunicorn .*8910' 2>/dev/null || echo "DOWN:no gunicorn"

if [ "$OK" = "1" ]; then
  echo "[OK] 8910 is up"
  curl -sSI http://127.0.0.1:8910/vsp4 | head -n 8 || true
  exit 0
fi

echo "[ERR] 8910 still down. Show last error log:"
tail -n 120 "$ERR" 2>/dev/null || echo "[WARN] no error log"
exit 1
