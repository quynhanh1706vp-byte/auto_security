#!/usr/bin/env bash
set -euo pipefail
SERVICE="vsp-ui-8910"
PORT=8910

echo "== 0) show who holds :$PORT (before) =="
sudo ss -ltnp | grep ":$PORT" || echo "[OK] no listener yet"

echo "== 1) stop service to avoid restart race =="
sudo systemctl stop "$SERVICE" 2>/dev/null || true

echo "== 2) find PID holding :$PORT =="
PIDS="$(sudo ss -ltnp 2>/dev/null | awk -v p=":$PORT" '$4 ~ p {print $0}' | sed -n 's/.*pid=\([0-9]\+\),.*/\1/p' | sort -u || true)"
if [ -n "${PIDS}" ]; then
  echo "[FOUND] PID(s) holding $PORT: ${PIDS}"
  echo "== commands =="
  for pid in $PIDS; do
    ps -p "$pid" -o pid,ppid,cmd --no-headers || true
  done

  echo "== 3) kill them (TERM then KILL) =="
  for pid in $PIDS; do
    sudo kill -TERM "$pid" 2>/dev/null || true
  done
  sleep 1
  for pid in $PIDS; do
    sudo kill -KILL "$pid" 2>/dev/null || true
  done
else
  echo "[OK] no PID found via ss parsing"
fi

echo "== 4) double-check port free =="
sudo ss -ltnp | grep ":$PORT" && echo "[WARN] still listener exists" || echo "[OK] port is free"

echo "== 5) reset failed state + restart service =="
sudo systemctl reset-failed "$SERVICE" 2>/dev/null || true
sudo systemctl restart "$SERVICE"

echo "== 6) wait a bit then verify listener =="
sleep 1
sudo ss -ltnp | grep ":$PORT" || true

echo "== 7) show service status (top) =="
sudo systemctl status "$SERVICE" --no-pager | sed -n '1,40p' || true

echo "== 8) healthz check =="
curl -sS -o /dev/null -w "HTTP=%{http_code}\n" http://127.0.0.1:${PORT}/healthz || true
curl -sS http://127.0.0.1:${PORT}/healthz ; echo || true
