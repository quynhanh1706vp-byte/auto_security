#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"

fix_file() {
  local f="$1"
  if [ ! -f "$f" ]; then
    return
  fi
  local bk="${f}.bak_runsapi_$(date +%Y%m%d_%H%M%S)"
  cp "$f" "$bk"
  sed -i 's#/api/vsp/runs_index_v3_v3#/api/vsp/runs_index_v3#g' "$f"
  echo "[OK] Đã sửa $f (backup: $bk)"
}

fix_file "$UI_ROOT/static/js/vsp_ui_main.js"
fix_file "$UI_ROOT/static/js/vsp_runs_v3.js"
fix_file "$UI_ROOT/static/js/vsp_patch_5tabs_v1.js"
fix_file "$UI_ROOT/static/js/vsp_dashboard_live_v2.js"
