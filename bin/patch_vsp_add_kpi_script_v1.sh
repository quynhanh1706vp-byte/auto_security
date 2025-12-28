#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

add_script() {
  local tpl="$1"
  if [ ! -f "$tpl" ]; then
    echo "[SKIP] $tpl không tồn tại"
    return 0
  fi

  if grep -q 'vsp_dashboard_kpi_v1.js' "$tpl"; then
    echo "[INFO] $tpl đã có KPI script, bỏ qua."
    return 0
  fi

  local backup="${tpl}.bak_kpi_$(date +%Y%m%d_%H%M%S)"
  cp "$tpl" "$backup"
  echo "[BACKUP] $tpl -> $backup"

  python - "$tpl" << 'PY'
import sys, io, os
path = sys.argv[1]
txt = open(path, encoding="utf-8").read()

needle = "</body>"
injection = '    <script src="/static/js/vsp_dashboard_kpi_v1.js"></script>\\n'

if needle not in txt:
    raise SystemExit(f"[ERR] Không tìm thấy </body> trong {path}")

txt = txt.replace(needle, injection + needle)
open(path, "w", encoding="utf-8").write(txt)
print(f"[OK] Đã chèn KPI script vào {path}")
PY
}

# Các template có thể được dùng cho Dashboard
add_script "$ROOT/templates/vsp_dashboard_2025.html"
add_script "$ROOT/templates/index.html"
add_script "$ROOT/templates/vsp_index.html"
