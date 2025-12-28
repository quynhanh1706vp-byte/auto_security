#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p455b_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need date; need curl
command -v sudo >/dev/null 2>&1 || { echo "[ERR] need sudo" | tee -a "$OUT/log.txt"; exit 2; }

log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUT/log.txt"; }

probe_quiet(){
  # probe nhẹ, không spam stderr
  curl -fsS --connect-timeout 0.6 --max-time 1.2 "$BASE/c/settings" -o /dev/null >/dev/null 2>&1
}

wait_up(){
  local tries=120
  local ok=0
  for i in $(seq 1 "$tries"); do
    if probe_quiet; then ok=1; echo "$i" >"$OUT/wait_up_tries.txt"; return 0; fi
    sleep 0.25 2>/dev/null || sleep 1
  done
  echo "$tries" >"$OUT/wait_up_tries.txt"
  return 1
}

fetch_with_retry(){
  local p="$1"
  local f="$OUT/$(echo "$p" | tr '/' '_').html"
  for i in $(seq 1 80); do
    if curl -fsS --connect-timeout 1 --max-time 4 "$BASE$p" -o "$f" 2>"$OUT/err$(echo "$p" | tr '/' '_').txt"; then
      log "[OK] $p"
      return 0
    fi
    sleep 0.25 2>/dev/null || sleep 1
  done
  log "[FAIL] $p"
  return 1
}

log "[INFO] OUT=$OUT BASE=$BASE SVC=$SVC"
log "[INFO] restart service"
sudo systemctl restart "$SVC" || true

log "[INFO] wait up (quiet)"
if wait_up; then
  t="$(cat "$OUT/wait_up_tries.txt" 2>/dev/null || echo "?")"
  log "[GREEN] service reachable (tries=$t)"
else
  log "[RED] service not reachable after restart"
  sudo systemctl status "$SVC" --no-pager -l | tee "$OUT/systemctl_status.txt" >/dev/null || true
  sudo journalctl -u "$SVC" -n 160 --no-pager | tee "$OUT/journal_tail.txt" >/dev/null || true
  exit 1
fi

pages=(/c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides)
fail=0
for p in "${pages[@]}"; do
  fetch_with_retry "$p" || fail=1
done

if [ "$fail" -eq 0 ]; then
  log "[PASS] COMMERCIAL_SMOKE"
else
  log "[AMBER] COMMERCIAL_SMOKE has FAILs"
fi
