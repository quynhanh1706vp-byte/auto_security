#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p491_headers_${TS}"
mkdir -p "$OUT"
TO="$(command -v timeout || true)"

tabs=(/c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides)

echo "== [P491v2] BASE=$BASE ==" | tee "$OUT/headers_report.txt"

# grep regex (safe with HTTP/)
want='^(HTTP/|Content-Type:|Content-Length:|Cache-Control:|Pragma:|Expires:|Content-Security-Policy:|X-Frame-Options:|X-Content-Type-Options:|Referrer-Policy:|Permissions-Policy:|Strict-Transport-Security:|Cross-Origin-Opener-Policy:|Cross-Origin-Resource-Policy:|Cross-Origin-Embedder-Policy:|X-VSP-)'

for p in "${tabs[@]}"; do
  echo "" | tee -a "$OUT/headers_report.txt" >/dev/null
  echo "== $p ==" | tee -a "$OUT/headers_report.txt"
  if [ -n "$TO" ]; then
    $TO 6s curl -sS -D - -o /dev/null "$BASE$p" \
      | tr -d '\r' \
      | grep -Ei "$want" \
      | tee -a "$OUT/headers_report.txt" || true
  else
    curl -sS -D - -o /dev/null "$BASE$p" \
      | tr -d '\r' \
      | grep -Ei "$want" \
      | tee -a "$OUT/headers_report.txt" || true
  fi
done

echo "" | tee -a "$OUT/headers_report.txt" >/dev/null
echo "[DONE] OUT=$OUT" | tee -a "$OUT/headers_report.txt"
