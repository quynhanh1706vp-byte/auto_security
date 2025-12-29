#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
MAX="${MAX_WAIT:-30}"

echo "== [OPS] restart+wait SVC=$SVC BASE=$BASE MAX=${MAX}s =="
sudo systemctl restart "$SVC"

ok=0
for i in $(seq 1 "$MAX"); do
  if sudo ss -lntp | grep -q ':8910'; then
    code="$(curl -sS --noproxy '*' -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$BASE/api/vsp/healthz" || true)"
    echo "try#$i LISTEN=1 code=$code"
    if [ "$code" = "200" ]; then ok=1; break; fi
  else
    echo "try#$i LISTEN=0"
  fi
  sleep 1
done

if [ "$ok" != "1" ]; then
  echo "[FAIL] not ready after ${MAX}s"
  sudo systemctl --no-pager -l status "$SVC" || true
  sudo journalctl -u "$SVC" -n 120 --no-pager || true
  exit 2
fi

echo "[OK] UI ready"
