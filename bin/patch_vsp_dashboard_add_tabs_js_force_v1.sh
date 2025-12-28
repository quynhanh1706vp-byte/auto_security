#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "${TPL}.bak_tabsjs_${TS}"
echo "[BACKUP] $TPL -> ${TPL}.bak_tabsjs_${TS}"

python3 - << 'PY'
from pathlib import Path

tpl = Path("templates/vsp_dashboard_2025.html")
text = tpl.read_text(encoding="utf-8")

if "vsp_tabs_simple_v1.js" in text:
    print("[INFO] Đã có vsp_tabs_simple_v1.js, không chèn thêm.")
else:
    if "</body>" in text:
        inject = '  <script src="/static/js/vsp_tabs_simple_v1.js"></script>\\n'
        inject += '  <script>console.log("[VSP_TABS_PATCH] tabs js loaded");</script>\\n'
        text = text.replace("</body>", inject + "</body>")
        print("[OK] Đã chèn vsp_tabs_simple_v1.js trước </body>.")
    else:
        print("[WARN] Không tìm thấy </body>, không sửa.")
tpl.write_text(text, encoding="utf-8")
PY
