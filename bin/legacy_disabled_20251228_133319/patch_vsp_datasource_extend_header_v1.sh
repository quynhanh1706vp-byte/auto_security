#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"
BACKUP="$TPL.bak_ds_header_ext_$(date +%Y%m%d_%H%M%S)"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy template: $TPL"
  exit 1
fi

cp "$TPL" "$BACKUP"
echo "[BACKUP] $TPL -> $BACKUP"

python - << 'PY'
from pathlib import Path
import re

tpl_path = Path("templates/vsp_dashboard_2025.html")
html = tpl_path.read_text(encoding="utf-8")

# Tìm thead của bảng Data Source: chứa đủ các th: Severity, Tool, Rule, Path, Line, Message, Run
pattern = re.compile(
    r"<thead>\s*<tr>\s*"
    r"<th>\s*Severity\s*</th>\s*"
    r"<th>\s*Tool\s*</th>\s*"
    r"<th>\s*Rule\s*</th>\s*"
    r"<th>\s*Path\s*</th>\s*"
    r"<th>\s*Line\s*</th>\s*"
    r"<th>\s*Message\s*</th>\s*"
    r"<th>\s*Run\s*</th>\s*"
    r"</tr>\s*</thead>",
    re.IGNORECASE | re.DOTALL,
)

new_thead = """
            <thead>
              <tr>
                <th>Severity</th>
                <th>Tool</th>
                <th>Rule</th>
                <th>Path</th>
                <th>Line</th>
                <th>Message</th>
                <th>Run</th>
                <th>CWE</th>
                <th>CVE</th>
                <th>Component</th>
                <th>Tags</th>
                <th>Fix</th>
              </tr>
            </thead>
""".rstrip()

new_html, n = pattern.subn(new_thead, html)
print(f"[PATCH] Replaced Data Source thead occurrences: {n}")
if n == 0:
    print("[WARN] Không tìm thấy thead Data Source để patch. Kiểm tra lại cấu trúc HTML.")
else:
    tpl_path.write_text(new_html, encoding="utf-8")
    print("[DONE] Updated Data Source header với 5 cột mới.")
PY

echo "[DONE] patch_vsp_datasource_extend_header_v1 completed."
