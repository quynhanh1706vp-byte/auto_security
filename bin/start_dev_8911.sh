#!/usr/bin/env bash
set -euo pipefail
PORT="${1:-8911}"

# validate numeric port
case "$PORT" in
  ''|*[!0-9]*)
    echo "[ERR] PORT must be numeric, got: $PORT"
    echo "Usage: bin/start_dev_8911.sh 8911"
    exit 2
    ;;
esac

if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
  echo "[ERR] invalid port range: $PORT"
  exit 2
fi

ROOT="/home/test/Data/SECURITY_BUNDLE"
UI="$ROOT/ui"
VENV="$ROOT/.venv"
mkdir -p "$UI/out_ci"

sudo fuser -k "${PORT}/tcp" 2>/dev/null || true

nohup "$VENV/bin/gunicorn" \
  -w 1 -k gthread --threads 4 \
  --timeout 60 --graceful-timeout 15 \
  --chdir "$UI" --pythonpath "$UI" \
  --bind 127.0.0.1:${PORT} \
  --access-logfile "$UI/out_ci/ui_${PORT}_access.log" \
  --error-logfile  "$UI/out_ci/ui_${PORT}_error.log" \
  wsgi_8910:application \
  > "$UI/out_ci/ui_${PORT}_nohup.log" 2>&1 &

sleep 1
echo "[OK] DEV gunicorn started on :$PORT"
sudo ss -ltnp | grep ":$PORT" || true
curl -sS -o /dev/null -w "HTTP=%{http_code}\n" "http://127.0.0.1:${PORT}/healthz" || true
echo "Logs: tail -n 80 $UI/out_ci/ui_${PORT}_error.log"
