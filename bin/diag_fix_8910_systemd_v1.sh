#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE"
UI="$ROOT/ui"
VENV="$ROOT/.venv"
SERVICE="vsp-ui-8910"
PORT=8910

echo "== A) sanity paths =="
ls -la "$UI/vsp_demo_app.py" "$UI/wsgi_8910.py" || true
mkdir -p "$UI/out_ci"
touch "$UI/out_ci/.writable_test" && rm -f "$UI/out_ci/.writable_test" && echo "[OK] out_ci writable"

echo "== B) venv gunicorn =="
if [ ! -x "$VENV/bin/python3" ]; then
  echo "[ERR] missing venv python: $VENV/bin/python3"
  exit 1
fi
"$VENV/bin/python3" -V
if ! "$VENV/bin/python3" -c "import gunicorn" >/dev/null 2>&1; then
  echo "[WARN] gunicorn missing -> installing..."
  "$VENV/bin/pip" install -U gunicorn
fi
"$VENV/bin/gunicorn" --version || true

echo "== C) python import check (most important) =="
echo "[1] import wsgi_8910"
"$VENV/bin/python3" -c "import wsgi_8910; print('wsgi_8910 import OK')"
echo "[2] load downstream (wsgi middleware already loads vsp_demo_app)"
"$VENV/bin/python3" -c "import wsgi_8910; print('application=', type(wsgi_8910.application))"

echo "== D) systemd status/logs =="
sudo systemctl stop "$SERVICE" 2>/dev/null || true
sudo fuser -k "${PORT}/tcp" 2>/dev/null || true
sudo systemctl restart "$SERVICE" || true

echo "--- systemctl status ---"
sudo systemctl status "$SERVICE" --no-pager | sed -n '1,120p' || true

echo "--- journalctl last 200 ---"
sudo journalctl -u "$SERVICE" -n 200 --no-pager || true

echo "== E) listener check =="
sudo ss -ltnp | grep ":$PORT" || echo "[WARN] still no listener on :$PORT"

echo "== F) run gunicorn foreground (single shot) to see crash reason =="
echo "NOTE: this runs for 3s then kills; if it prints error -> that's the root cause"
set +e
"$VENV/bin/gunicorn" -w 1 -k gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir "$UI" --pythonpath "$UI" \
  --bind 127.0.0.1:${PORT} \
  --error-logfile - --access-logfile - \
  wsgi_8910:application &
PID=$!
sleep 3
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
set -e
echo "[DONE] If you saw import/traceback above, paste it to fix precisely."
