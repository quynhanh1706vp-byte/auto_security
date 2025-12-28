#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"
BACKUP="$TPL.bak_add_findings_script_$(date +%Y%m%d_%H%M%S)"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy template: $TPL"
  exit 1
fi

cp "$TPL" "$BACKUP"
echo "[BACKUP] $TPL -> $BACKUP"

python - << 'PY'
from pathlib import Path

tpl_path = Path("templates/vsp_dashboard_2025.html")
html = tpl_path.read_text(encoding="utf-8")

if 'vsp_dashboard_findings_v1.js' in html:
    print("[INFO] Script đã tồn tại, bỏ qua.")
else:
    marker = "</body>"
    if marker not in html:
        raise SystemExit("[ERR] Không thấy </body> trong template.")
    script = '  <script src="/static/js/vsp_dashboard_findings_v1.js"></script>\n'
    html = html.replace(marker, script + "</body>")
    tpl_path.write_text(html, encoding="utf-8")
    print("[PATCH] Đã chèn script vsp_dashboard_findings_v1.js trước </body>.")
PY

echo "[DONE] patch_vsp_dashboard_add_findings_script_only_v1 completed."
