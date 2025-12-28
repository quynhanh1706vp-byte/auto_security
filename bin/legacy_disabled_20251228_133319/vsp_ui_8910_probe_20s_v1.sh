#!/usr/bin/env bash
set -euo pipefail
echo "== probe 20s /api/vsp/runs?limit=1 =="
bad=0
for i in $(seq 1 80); do
  ts="$(date +%T.%3N)"
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 1 http://127.0.0.1:8910/api/vsp/runs?limit=1 2>/dev/null || echo FAIL)"
  echo "$ts code=$code"
  if [ "$code" = "FAIL" ] || [ "$code" = "000" ]; then bad=$((bad+1)); fi
  sleep 0.25
done
echo "bad=$bad"
if [ "$bad" -gt 0 ]; then
  echo "== journalctl last 80 =="
  sudo journalctl -u vsp-ui-8910.service --no-pager -n 80 || true
  echo "== error.log tail 120 =="
  tail -n 120 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log 2>/dev/null || true
fi
