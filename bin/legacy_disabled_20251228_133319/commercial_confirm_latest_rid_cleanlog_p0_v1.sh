#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

ERR="out_ci/ui_8910.error.log"
TS="$(date +%Y%m%d_%H%M%S)"

# backup log
if [ -f "$ERR" ]; then
  cp -f "$ERR" "$ERR.bak_clean_${TS}"
  echo "[BACKUP] $ERR.bak_clean_${TS}"
fi

# clear log to remove old KeyError spam
: > "$ERR"
echo "[OK] cleared $ERR"

# restart hard reset
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh >/dev/null

# hit endpoint multiple times
echo "== HIT latest_rid_v1 x20 =="
for i in $(seq 1 20); do
  code="$(curl -sS -o /tmp/latest_rid.json -w '%{http_code}' http://127.0.0.1:8910/api/vsp/latest_rid_v1 || true)"
  echo "[$i] http=$code body=$(cat /tmp/latest_rid.json | tr -d '\n' | head -c 160)"
done

echo "== GREP KeyError after clean run =="
if grep -n "KeyError: 'run_id'\|api_vsp_latest_rid_v1" "$ERR" | tail -n 20; then
  echo "[WARN] still seeing errors above (new)."
else
  echo "[OK] no KeyError/run_id in fresh error.log"
fi
