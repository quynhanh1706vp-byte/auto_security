#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
PORT=8910
BASE="http://127.0.0.1:${PORT}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo
need systemctl
need ss
need awk
command -v ps >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

echo "== [1] stop service (so we can safely kill old listeners) =="
sudo systemctl stop "$SVC" || true
sudo systemctl reset-failed "$SVC" || true

echo "== [2] list & kill ANY listeners on :$PORT =="
ss -lptn "sport = :$PORT" || true
PIDS="$(ss -lptn "sport = :$PORT" 2>/dev/null | awk -F'pid=|,' '/pid=/{print $2}' | sort -u | tr '\n' ' ')"

if [ -n "${PIDS// }" ]; then
  echo "[WARN] killing listeners: $PIDS"
  for p in $PIDS; do
    echo "--- PID $p ---"
    ps -p "$p" -o pid,ppid,etime,cmd || true
    sudo kill -TERM "$p" 2>/dev/null || true
  done
  sleep 1
  P2="$(ss -lptn "sport = :$PORT" 2>/dev/null | awk -F'pid=|,' '/pid=/{print $2}' | sort -u | tr '\n' ' ')"
  if [ -n "${P2// }" ]; then
    echo "[WARN] force kill: $P2"
    for p in $P2; do sudo kill -KILL "$p" 2>/dev/null || true; done
    sleep 1
  fi
fi

echo "== [3] confirm port free =="
ss -lptn "sport = :$PORT" || echo "[OK] port $PORT is free"

echo "== [4] start service =="
sudo systemctl start "$SVC" || true
sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
sudo systemctl status "$SVC" -n 15 --no-pager || true

echo "== [5] confirm listener belongs to service now =="
ss -lptn "sport = :$PORT" || true

echo "== [6] smoke =="
curl -fsS --connect-timeout 1 --max-time 5 "$BASE/api/vsp/rid_latest" | head -c 220; echo || true

echo "[DONE] v24e"
