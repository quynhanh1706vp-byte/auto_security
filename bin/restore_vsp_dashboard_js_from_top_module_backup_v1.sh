#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

restore_one() {
  local NAME="$1"
  local FILE="$ROOT/static/js/$NAME"

  if [ ! -f "$FILE".bak_top_module_* ] 2>/dev/null && ! ls "$FILE".bak_top_module_* >/dev/null 2>&1; then
    echo "[WARN] Không tìm thấy backup cho $NAME (.bak_top_module_*) – bỏ qua."
    return
  fi

  local BAK
  BAK="$(ls -1t "$FILE".bak_top_module_* 2>/dev/null | head -n1 || true)"
  if [ -z "$BAK" ]; then
    echo "[WARN] Không tìm thấy backup cho $NAME – bỏ qua."
    return
  fi

  cp "$BAK" "$FILE"
  echo "[RESTORE] $BAK -> $FILE"
}

restore_one "vsp_dashboard_kpi_v1.js"
restore_one "vsp_dashboard_charts_v1.js"

echo "[DONE] restore_vsp_dashboard_js_from_top_module_backup_v1.sh hoàn tất."
