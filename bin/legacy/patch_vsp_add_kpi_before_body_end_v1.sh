#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"

patch_tpl() {
  local tpl="$1"
  if [ ! -f "$tpl" ]; then
    echo "[SKIP] $tpl không tồn tại"
    return 0
  fi

  if grep -q 'vsp_dashboard_kpi_v1.js' "$tpl"; then
    echo "[INFO] $tpl đã có KPI script, bỏ qua."
    return 0
  fi

  local backup="${tpl}.bak_kpi_body_$(date +%Y%m%d_%H%M%S)"
  cp "$tpl" "$backup"
  echo "[BACKUP] $tpl -> $backup"

  python - "$tpl" << 'PY'
import sys
path = sys.argv[1]
txt = open(path, encoding="utf-8").read()

needle = "</body>"
inject = '    <script src="/static/js/vsp_dashboard_kpi_v1.js"></script>\n'

if needle not in txt:
    print(f"[WARN] Không tìm thấy </body> trong {path}, bỏ qua.")
else:
    txt = txt.replace(needle, inject + needle)
    open(path, "w", encoding="utf-8").write(txt)
    print(f"[OK] Đã chèn KPI script trước </body> trong {path}")
PY
}

patch_tpl "$UI_ROOT/templates/index.html"
patch_tpl "$UI_ROOT/templates/vsp_index.html"
patch_tpl "$UI_ROOT/templates/vsp_dashboard_2025.html"
