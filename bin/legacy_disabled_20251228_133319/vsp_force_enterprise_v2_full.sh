#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT/templates/vsp_dashboard_2025.html"
SRC="$ROOT/templates/vsp_5tabs_enterprise_v2.html"

if [ ! -f "$SRC" ]; then
  echo "[ERR] Không thấy $SRC – cần tạo vsp_5tabs_enterprise_v2.html trước."
  exit 1
fi

# Backup bản hiện tại (dù có body hay không)
if [ -f "$TPL" ]; then
  cp "$TPL" "$TPL.bak_force_enterprise_v2_$(date +%Y%m%d_%H%M%S)"
  echo "[BACKUP] -> $TPL.bak_force_enterprise_v2_*"
fi

python - << 'PY'
from pathlib import Path
import re

tpl = Path("templates/vsp_dashboard_2025.html")
src = Path("templates/vsp_5tabs_enterprise_v2.html")

src_txt = src.read_text(encoding="utf-8")

# Các script JS VSP cần load trong <head>
extra_scripts = """
  <!-- VSP 2025 core JS -->
  <script src="/static/js/vsp_tabs_hash_router_v1.js" defer></script>
  <script src="/static/js/vsp_dashboard_enhance_v1.js" defer></script>
  <script src="/static/js/vsp_dashboard_cleanup_v1.js" defer></script>
  <script src="/static/js/vsp_dashboard_charts_v2.js" defer></script>

  <!-- Tabs V2 -->
  <script src="/static/js/vsp_runs_tab_simple_v2.js" defer></script>
  <script src="/static/js/vsp_datasource_tab_simple_v1.js" defer></script>
  <script src="/static/js/vsp_settings_tab_simple_v1.js" defer></script>
  <script src="/static/js/vsp_rules_tab_simple_v1.js" defer></script>
"""

def inject_scripts(html: str) -> str:
    # Nếu có </head> thì chèn trước đó
    if "</head>" in html.lower():
        new_html, n = re.subn(
            r"</head>",
            extra_scripts + "\n</head>",
            html,
            count=1,
            flags=re.IGNORECASE,
        )
        if n > 0:
            return new_html
    # Nếu không tìm thấy <head>, cứ append scripts lên đầu file
    return extra_scripts + "\n" + html

new_tpl = inject_scripts(src_txt)
tpl.write_text(new_tpl, encoding="utf-8")
print("[OK] Đã ghi đè templates/vsp_dashboard_2025.html bằng enterprise V2 + JS VSP.")
PY
