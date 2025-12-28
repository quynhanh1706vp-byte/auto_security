#!/usr/bin/env bash
set -euo pipefail

TPL="/home/test/Data/SECURITY_BUNDLE/ui/templates/dashboard.html"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy template: $TPL" >&2
  exit 1
fi

echo "[i] Wiring tool chart scripts vào $TPL"

add_tag() {
  local jsname="$1"
  if grep -q "$jsname" "$TPL"; then
    echo "[i] $jsname đã có trong dashboard.html, bỏ qua."
  else
    printf '  <script src="{{ url_for('"'"'static'"'"', filename='"'"'%s'"'"') }}"></script>\n' "$jsname" >> "$TPL"
    echo "[OK] Đã thêm script $jsname vào dashboard.html"
  fi
}

add_tag "tool_config.js"
add_tag "tool_chart.js"
add_tag "tool_chart_auto.js"

echo "[OK] wire_tool_chart_to_dashboard done."
