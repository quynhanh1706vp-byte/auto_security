#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"
BACKUP="$TPL.bak_nuke_findings_$(date +%Y%m%d_%H%M%S)"

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

# 1) Xoá mọi section có id="vsp-dashboard-findings-zone"
pattern_section = re.compile(
    r'\s*<section[^>]*id="vsp-dashboard-findings-zone"[^>]*>.*?</section>',
    re.DOTALL | re.IGNORECASE,
)
html, n1 = pattern_section.subn("", html)
print(f"[NUKE] Removed findings <section> count = {n1}")

# 2) Xoá mọi script vsp_dashboard_findings_v1.js
pattern_script = re.compile(
    r'\s*<script\s+src="/static/js/vsp_dashboard_findings_v1\.js"></script>',
    re.IGNORECASE,
)
html, n2 = pattern_script.subn("", html)
print(f"[NUKE] Removed findings <script> count = {n2}")

tpl_path.write_text(html, encoding="utf-8")
print("[DONE] Template cleaned – Dashboard chỉ còn KPI + charts như cũ.")
PY

echo "[DONE] nuke_vsp_dashboard_findings_ui_v1 completed."
