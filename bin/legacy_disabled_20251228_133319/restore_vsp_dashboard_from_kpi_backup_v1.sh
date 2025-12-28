#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[VSP_RESTORE_KPI]"
UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL_DIR="$UI_ROOT/templates"
TARGET="$TPL_DIR/vsp_dashboard_2025.html"

echo "$LOG_PREFIX UI_ROOT = $UI_ROOT"
echo "$LOG_PREFIX TARGET = $TARGET"

# tìm bản backup kiểu ...bak_kpi_force_v2_*
LATEST="$(ls -1 "$TPL_DIR"/vsp_dashboard_2025.html.bak_kpi_force_v2_* 2>/dev/null | sort | tail -n1 || true)"

if [ -z "$LATEST" ]; then
  echo "$LOG_PREFIX [ERR] Không tìm thấy backup kiểu vsp_dashboard_2025.html.bak_kpi_force_v2_*"
  exit 1
fi

echo "$LOG_PREFIX Sẽ restore từ: $LATEST"
cp "$LATEST" "$TARGET"
echo "$LOG_PREFIX [DONE] Đã copy $LATEST -> $TARGET"
