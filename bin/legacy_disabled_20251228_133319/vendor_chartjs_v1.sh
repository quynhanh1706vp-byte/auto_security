#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

OUT="static/vendor"
mkdir -p "$OUT"

DST="$OUT/chart.umd.min.js"

# Try a few CDNs
URLS=(
  "https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js"
  "https://unpkg.com/chart.js@4.4.7/dist/chart.umd.min.js"
  "https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.7/chart.umd.min.js"
)

ok=0
for u in "${URLS[@]}"; do
  echo "[DL] $u"
  if curl -fsSL "$u" -o "$DST.tmp"; then
    if grep -q "Chart" "$DST.tmp"; then
      mv -f "$DST.tmp" "$DST"
      ok=1
      break
    fi
  fi
done

rm -f "$DST.tmp" 2>/dev/null || true

if [ "$ok" -ne 1 ]; then
  echo "[ERR] download Chart.js failed"
  exit 1
fi

echo "[OK] wrote $DST ($(wc -c < "$DST") bytes)"
