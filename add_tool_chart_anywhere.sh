#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TPL="$ROOT/templates/index.html"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy template: $TPL" >&2
  exit 1
fi

if grep -q 'id="toolChart"' "$TPL"; then
  echo "[i] index.html đã có #toolChart, không chèn nữa."
  exit 0
fi

echo "[i] Chèn <div id=\"toolChart\"> trước </body> trong $TPL"

# chèn container ngay trước </body>
awk '
  /<\/body>/ && !added {
    print "  <div id=\"toolChart\" class=\"tool-chart-block\"></div>";
    print;
    added=1;
    next;
  }
  { print }
' "$TPL" > "$TPL.tmp"

if ! grep -q 'id="toolChart"' "$TPL.tmp"; then
  echo "[WARN] Không chèn được #toolChart (không thấy </body>?)." >&2
  rm -f "$TPL.tmp"
  exit 1
fi

mv "$TPL.tmp" "$TPL"
echo "[OK] Đã chèn container #toolChart vào $TPL"
