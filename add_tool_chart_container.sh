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

echo "[i] Chèn <div id=\"toolChart\"> vào block 'Findings by tool' trong $TPL"

awk 'BEGIN{IGNORECASE=1}
  /Findings by tool/ && !added {
    print;
    print "        <div id=\"toolChart\" class=\"tool-chart-block\"></div>";
    added=1;
    next;
  }
  { print }
' "$TPL" > "$TPL.tmp"

if ! grep -q 'id="toolChart"' "$TPL.tmp"; then
  echo "[WARN] Không tìm được dòng chứa \"Findings by tool\" để chèn. Không thay đổi file." >&2
  rm -f "$TPL.tmp"
  exit 1
fi

mv "$TPL.tmp" "$TPL"
echo "[OK] Đã chèn container #toolChart vào $TPL"
