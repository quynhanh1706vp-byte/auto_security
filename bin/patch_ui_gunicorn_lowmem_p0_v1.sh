#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="bin/ui_restart_8910_no_restore_v1.sh"
if [ -f "$F" ]; then
  cp -f "$F" "$F.bak_lowmem_${TS}"
  echo "[BACKUP] $F.bak_lowmem_${TS}"

  # workers/threads
  sed -i -E 's/--workers[[:space:]]+[0-9]+/--workers 1/g' "$F"
  sed -i -E 's/--threads[[:space:]]+[0-9]+/--threads 2/g' "$F"

  # timeout
  sed -i -E 's/--timeout[[:space:]]+[0-9]+/--timeout 180/g' "$F"
  sed -i -E 's/--graceful-timeout[[:space:]]+[0-9]+/--graceful-timeout 30/g' "$F"

  # add max-requests if missing
  if ! grep -q -- '--max-requests' "$F"; then
    sed -i -E 's/(gunicorn[[:space:]].*application[[:space:]]*\\\s*)/\1\n  --max-requests 200 --max-requests-jitter 50 \\\n/g' "$F" || true
  fi

  echo "[OK] patched $F to low-mem mode"
else
  echo "[WARN] missing $F (skip patch). You are using inline gunicorn in scripts elsewhere."
fi

echo "== restart 8910 =="
bash bin/ui_restart_8910_no_restore_v1.sh || true

echo "== verify =="
ss -lntp | grep ':8910' || true
echo "[NEXT] Clear log, Ctrl+Shift+R, click 5 tabs, then tail error log."
