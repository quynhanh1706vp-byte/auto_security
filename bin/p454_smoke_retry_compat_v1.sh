#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p454_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need date; need curl; need sleep || true
command -v ss >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUT/log.txt"; }

log "[INFO] OUT=$OUT BASE=$BASE"
log "[INFO] curl_version=$(curl --version | head -n1)"

# quick port view (optional)
if command -v ss >/dev/null 2>&1; then
  (ss -lntp 2>/dev/null | grep -E '(:8910\b)' || true) | tee "$OUT/ss_8910.txt" >/dev/null
fi

fetch_with_retry(){
  local p="$1"
  local f="$OUT/$(echo "$p" | tr '/' '_').html"
  local ok=0

  for i in $(seq 1 80); do
    if curl -fsS --connect-timeout 1 --max-time 3 "$BASE$p" -o "$f" 2>"$OUT/err$(echo "$p" | tr '/' '_').txt"; then
      ok=1
      break
    fi
    # sleep ngắn; coreutils sleep thường support số thực, nếu không thì vẫn OK với 1
    sleep 0.25 2>/dev/null || sleep 1
  done

  if [ "$ok" -eq 1 ]; then
    log "[OK] $p"
    return 0
  else
    log "[FAIL] $p (see $OUT/err$(echo "$p" | tr '/' '_').txt)"
    return 1
  fi
}

pages=(/c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides)

fail=0
for p in "${pages[@]}"; do
  fetch_with_retry "$p" || fail=1
done

if [ "$fail" -eq 0 ]; then
  log "[GREEN] smoke PASS"
else
  log "[AMBER] smoke has FAILs; check $OUT/*"
fi
