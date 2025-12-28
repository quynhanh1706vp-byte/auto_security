#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

PIDFILE="out_ci/ui_8910.pid"
KEEP="$(cat "$PIDFILE" 2>/dev/null || true)"

echo "[INFO] keep_master=${KEEP:-<none>}"

# list pids listening on 8910
PIDS="$(ss -ltnp 2>/dev/null | awk '/:8910/ {print $NF}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u)"
echo "[INFO] listening_pids=${PIDS:-<none>}"

# keep master + its children; kill the rest
for p in $PIDS; do
  if [ -n "${KEEP:-}" ] && [ "$p" = "$KEEP" ]; then
    echo "[KEEP] pid=$p (master)"
    continue
  fi
  if [ -n "${KEEP:-}" ] && [ "$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')" = "$KEEP" ]; then
    echo "[KEEP] pid=$p (child of master)"
    continue
  fi
  echo "[KILL] pid=$p"
  kill -KILL "$p" 2>/dev/null || true
done

sleep 0.5
echo "== after purge =="
ss -ltnp | grep ':8910' || echo "8910 not listening"
