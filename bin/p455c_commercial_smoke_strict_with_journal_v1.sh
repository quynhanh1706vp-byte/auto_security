#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p455c_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need date; need curl
command -v sudo >/dev/null 2>&1 || { echo "[ERR] need sudo" | tee -a "$OUT/log.txt"; exit 2; }
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] need systemctl" | tee -a "$OUT/log.txt"; exit 2; }

echo "[$(date +%H:%M:%S)] [INFO] OUT=$OUT BASE=$BASE SVC=$SVC" | tee -a "$OUT/log.txt"
echo "[$(date +%H:%M:%S)] [INFO] restart service" | tee -a "$OUT/log.txt"
sudo systemctl restart "$SVC" || true

# wait up to 120s
ok=0
for i in $(seq 1 60); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" -o /dev/null; then ok=1; break; fi
  sleep 2
done

if [ "$ok" -ne 1 ]; then
  echo "[$(date +%H:%M:%S)] [RED] service not reachable after restart" | tee -a "$OUT/log.txt"
  sudo systemctl status "$SVC" --no-pager > "$OUT/systemctl_status.txt" 2>&1 || true
  sudo journalctl -u "$SVC" -n 200 --no-pager > "$OUT/journal_tail.txt" 2>&1 || true
  exit 3
fi

echo "[$(date +%H:%M:%S)] [INFO] wait up OK" | tee -a "$OUT/log.txt"

pages=(/vsp5 /runs /data_source /settings /rule_overrides /c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides)
bad=0
for p in "${pages[@]}"; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 6 "$BASE$p" || echo 000)"
  if [ "$code" != "200" ]; then
    echo "[RED] $code $p" | tee -a "$OUT/bad.txt"
    bad=$((bad+1))
  else
    echo "[OK]  $code $p" | tee -a "$OUT/log.txt"
  fi
done

[ "$bad" -eq 0 ] || exit 4
echo "[GREEN] P455c PASS (restart + tabs all 200)" | tee -a "$OUT/log.txt"
