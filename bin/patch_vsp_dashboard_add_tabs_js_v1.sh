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

tpl = Path(r"templates/vsp_dashboard_2025.html")
text = tpl.read_text(encoding="utf-8")

needle = 'vsp_dashboard_charts_v1.js"></script>'
line = '<script src="/static/js/vsp_tabs_simple_v1.js"></script>'

if "vsp_tabs_simple_v1.js" in text:
    print("[INFO] Đã có vsp_tabs_simple_v1.js trong template, bỏ qua chèn script.")
else:
    if needle in text:
        text = text.replace(
            needle,
            needle + "\n  " + line
        )
        print("[OK] Đã chèn vsp_tabs_simple_v1.js sau vsp_dashboard_charts_v1.js")
    else:
        # fallback: chèn trước </body>
        if "</body>" in text:
            text = text.replace(
                "</body>",
                f"  {line}\n</body>"
            )
            print("[OK] Đã chèn vsp_tabs_simple_v1.js trước </body> (fallback).")
        else:
            print("[WARN] Không tìm thấy vị trí chèn hợp lý, không sửa file.")
tpl.write_text(text, encoding="utf-8")
PY
