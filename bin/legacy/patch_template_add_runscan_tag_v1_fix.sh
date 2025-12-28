#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT/templates/vsp_dashboard_2025.html"
TAG='<script src="/static/js/vsp_runs_trigger_scan_ui_v1.js" defer></script>'

if [ ! -f "$TPL" ]; then
  echo "[PATCH][ERR] Không tìm thấy template: $TPL"
  exit 1
fi

# backup
BK="${TPL}.bak_runscan_tag_fix_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$BK"
echo "[BACKUP] $BK"

# nếu đã có thì thôi
if grep -q 'vsp_runs_trigger_scan_ui_v1\.js' "$TPL"; then
  echo "[PATCH] Script tag đã tồn tại, bỏ qua."
  exit 0
fi

# chèn trước </body>
if grep -q '</body>' "$TPL"; then
  # dùng sed portable: tạo file tmp rồi move
  TMP="$(mktemp)"
  sed "s#</body>#  ${TAG}\n</body>#g" "$TPL" > "$TMP"
  mv "$TMP" "$TPL"
  echo "[PATCH] Đã chèn script tag vào trước </body>."
else
  echo "[PATCH][ERR] Không tìm thấy </body> trong template."
  exit 1
fi
