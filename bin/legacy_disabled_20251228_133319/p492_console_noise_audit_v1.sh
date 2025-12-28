#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p492_console_${TS}"
mkdir -p "$OUT"

ROOT="static/js"
[ -d "$ROOT" ] || { echo "[ERR] missing $ROOT"; exit 2; }

echo "== [P492] console noise audit ==" | tee "$OUT/report.txt"
echo "" | tee -a "$OUT/report.txt" >/dev/null

echo "== console.* counts (top 30) ==" | tee -a "$OUT/report.txt"
grep -RhoE '\bconsole\.(log|debug|info|warn|error)\b' "$ROOT" \
  | sed -E 's/.*console\./console./' \
  | sort | uniq -c | sort -nr | head -n 30 | tee -a "$OUT/report.txt" || true

echo "" | tee -a "$OUT/report.txt" >/dev/null
echo "== files with console.* (top 30) ==" | tee -a "$OUT/report.txt"
grep -RInE '\bconsole\.(log|debug|info|warn|error)\b' "$ROOT" \
  | awk -F: '{print $1}' \
  | sort | uniq -c | sort -nr | head -n 30 | tee -a "$OUT/report.txt" || true

echo "" | tee -a "$OUT/report.txt" >/dev/null
echo "== files with [P###] markers (top 30) ==" | tee -a "$OUT/report.txt"
grep -RInE '\[P[0-9]{2,5}[a-z]?\]' "$ROOT" \
  | awk -F: '{print $1}' \
  | sort | uniq -c | sort -nr | head -n 30 | tee -a "$OUT/report.txt" || true

echo "" | tee -a "$OUT/report.txt" >/dev/null
echo "== sample lines (first 50) ==" | tee -a "$OUT/report.txt"
grep -RInE '\bconsole\.(log|debug|info|warn|error)\b|\[P[0-9]{2,5}[a-z]?\]' "$ROOT" \
  | head -n 50 | tee -a "$OUT/report.txt" || true

echo "" | tee -a "$OUT/report.txt" >/dev/null
echo "[DONE] OUT=$OUT" | tee -a "$OUT/report.txt"
