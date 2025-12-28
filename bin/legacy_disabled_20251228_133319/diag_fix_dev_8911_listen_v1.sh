#!/usr/bin/env bash
set -euo pipefail
PORT=8911
SVC="vsp-ui-8911-dev"
ERR="out_ci/ui_${PORT}_error.log"

echo "== 1) systemd status (top) =="
sudo systemctl status "$SVC" --no-pager | sed -n '1,35p' || true

echo "== 2) listener check =="
sudo ss -ltnp | grep ":$PORT" || echo "[WARN] no LISTEN on :$PORT"

echo "== 3) gunicorn processes =="
ps -ef | grep -E "gunicorn.*:${PORT}|gunicorn.*${SVC}" | grep -v grep || true

echo "== 4) error log tail (most important) =="
if [ -f "$ERR" ]; then
  tail -n 160 "$ERR" || true
else
  echo "[WARN] missing $ERR"
fi

echo "== 5) if bind conflict -> free port and restart =="
if [ -f "$ERR" ] && grep -qiE "Address already in use|Connection in use|Errno 98" "$ERR"; then
  echo "[FIX] Detected bind conflict -> killing :$PORT then restart $SVC"
  sudo fuser -k "${PORT}/tcp" 2>/dev/null || true
  sleep 1
  sudo systemctl restart "$SVC"
fi

echo "== 6) final verify =="
sudo ss -ltnp | grep ":$PORT" || echo "[WARN] still no LISTEN on :$PORT"
curl -sS -o /dev/null -w "healthz_${PORT} HTTP=%{http_code}\n" "http://127.0.0.1:${PORT}/healthz" || true
