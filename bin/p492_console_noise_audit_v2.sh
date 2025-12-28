#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p492_console_live_${TS}"
mkdir -p "$OUT"

ROOT="static/js"
[ -d "$ROOT" ] || { echo "[ERR] missing $ROOT"; exit 2; }

# chỉ lấy JS "live": bỏ *.bak*, bỏ thư mục backup_*
LIVE_LIST="$OUT/live_js_files.txt"
find "$ROOT" -type f -name "*.js" \
  ! -name "*.bak*" \
  ! -path "*/backup_*/*" \
  > "$LIVE_LIST"

echo "== [P492v2] console noise (LIVE only) ==" | tee "$OUT/report.txt"
echo "live_files=$(wc -l < "$LIVE_LIST" | tr -d ' ')" | tee -a "$OUT/report.txt"
echo "" | tee -a "$OUT/report.txt" >/dev/null

echo "== console.* totals (LIVE) ==" | tee -a "$OUT/report.txt"
xargs -a "$LIVE_LIST" grep -hoE '\bconsole\.(log|debug|info|warn|error)\b' \
  | sed -E 's/.*console\./console./' \
  | sort | uniq -c | sort -nr | tee -a "$OUT/report.txt" || true

echo "" | tee -a "$OUT/report.txt" >/dev/null
echo "== top files by console.* (LIVE) ==" | tee -a "$OUT/report.txt"
xargs -a "$LIVE_LIST" grep -nE '\bconsole\.(log|debug|info|warn|error)\b' \
  | awk -F: '{print $1}' \
  | sort | uniq -c | sort -nr | head -n 30 | tee -a "$OUT/report.txt" || true

echo "" | tee -a "$OUT/report.txt" >/dev/null
echo "== files with [P###] markers (LIVE) ==" | tee -a "$OUT/report.txt"
xargs -a "$LIVE_LIST" grep -nE '\[P[0-9]{2,5}[a-z]?\]' \
  | awk -F: '{print $1}' \
  | sort | uniq -c | sort -nr | head -n 30 | tee -a "$OUT/report.txt" || true

echo "" | tee -a "$OUT/report.txt" >/dev/null
echo "[DONE] OUT=$OUT" | tee -a "$OUT/report.txt"
