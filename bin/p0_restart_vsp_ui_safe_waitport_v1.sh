#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need systemctl; need curl; need bash; need sleep

echo "== [daemon-reload] =="
sudo systemctl daemon-reload || true

echo "== [stop] $SVC =="
sudo systemctl stop "$SVC" || true

# best-effort: chờ port nhả ra (tránh gunicorn báo Address already in use)
for i in $(seq 1 40); do
  if curl -fsS --connect-timeout 1 --max-time 1 "$BASE/healthz" >/dev/null 2>&1; then
    echo "[WAIT] still serving, sleep..."
    sleep 0.2
    continue
  fi
  break
done

echo "== [start] $SVC =="
sudo systemctl start "$SVC"

echo "== [wait port] =="
for i in $(seq 1 90); do
  if curl -fsS --connect-timeout 1 --max-time 1 "$BASE/" >/dev/null 2>&1; then
    echo "[OK] UI up: $BASE"
    exit 0
  fi
  sleep 0.25
done

echo "[ERR] UI not up after wait"
sudo systemctl status "$SVC" --no-pager -l | tail -n 80 || true
exit 1
