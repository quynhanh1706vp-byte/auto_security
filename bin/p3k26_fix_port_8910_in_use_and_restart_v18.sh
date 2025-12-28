#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PORT=8910
PIDFILE="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_${PORT}.pid"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need bash
need sudo
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] missing systemctl"; exit 2; }
command -v ss >/dev/null 2>&1 || { echo "[ERR] missing ss"; exit 2; }
command -v awk >/dev/null 2>&1 || true
command -v sed >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true
command -v ps >/dev/null 2>&1 || true

echo "== [1] stop service =="
sudo systemctl stop "$SVC" || true
sudo systemctl reset-failed "$SVC" || true

echo "== [2] find listeners on :$PORT =="
ss -lptn "sport = :$PORT" || true

PIDS="$(ss -lptn "sport = :$PORT" 2>/dev/null | awk -F'pid=|,' '/pid=/{print $2}' | sort -u | tr '\n' ' ')"
if [ -n "${PIDS// }" ]; then
  echo "[WARN] port $PORT still in use by PID(s): $PIDS"
  for p in $PIDS; do
    echo "--- PID $p ---"
    ps -p "$p" -o pid,ppid,etime,cmd || true
  done

  echo "== [3] terminate listeners (TERM then KILL) =="
  for p in $PIDS; do sudo kill -TERM "$p" 2>/dev/null || true; done
  sleep 1
  PIDS2="$(ss -lptn "sport = :$PORT" 2>/dev/null | awk -F'pid=|,' '/pid=/{print $2}' | sort -u | tr '\n' ' ')"
  if [ -n "${PIDS2// }" ]; then
    echo "[WARN] still holding port, force kill: $PIDS2"
    for p in $PIDS2; do sudo kill -KILL "$p" 2>/dev/null || true; done
    sleep 1
  fi
fi

echo "== [4] cleanup stale pidfile =="
if [ -f "$PIDFILE" ]; then
  echo "[INFO] removing $PIDFILE"
  sudo rm -f "$PIDFILE" || true
fi

echo "== [5] start service =="
sudo systemctl start "$SVC" || true
sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"

echo "== [6] verify port bind =="
ss -lptn "sport = :$PORT" || true

echo "== [7] smoke (5s) =="
curl -sv --connect-timeout 1 --max-time 5 "$BASE/api/vsp/rid_latest" -o /tmp/rid_latest.json 2>&1 | sed -n '1,70p'
echo "--- /tmp/rid_latest.json (first 220 bytes) ---"
head -c 220 /tmp/rid_latest.json || true; echo

echo "[DONE] p3k26_fix_port_8910_in_use_and_restart_v18"
