#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TPL="$ROOT/templates/index.html"

JS_TAG='tool_chart_auto.js'

if [ -f "$TPL" ]; then
  if grep -q "$JS_TAG" "$TPL"; then
    echo "[i] index.html đã có tool_chart_auto.js rồi."
  else
    echo "[i] Thêm <script> tool_chart_auto.js vào $TPL"
    printf '  <script src="{{ url_for('"'"'static'"'"', filename='"'"'tool_chart_auto.js'"'"') }}"></script>\n' >> "$TPL"
  fi
else
  echo "[WARN] Không tìm thấy template: $TPL" >&2
fi

echo "[OK] setup_tool_chart_auto done."
