#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "[INFO] ROOT = $ROOT"
echo "[INFO] Scanning templates/*.html ..."

python - << 'PY'
from pathlib import Path
import re
from datetime import datetime

tpl_dir = Path("templates")
ts = datetime.now().strftime("%Y%m%d_%H%M%S")

block = '''    <script src="/static/js/vsp_dashboard_kpi_v1.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script src="/static/js/vsp_dashboard_charts_v1.js"></script>
'''

for tpl in tpl_dir.glob("*.html"):
    text = tpl.read_text(encoding="utf-8")

    if "vsp_dashboard_kpi_v1.js" not in text:
        continue
    if "vsp_dashboard_charts_v1.js" in text:
        print(f"[SKIP] {tpl} đã có charts script.")
        continue

    print(f"[PATCH] Đang patch {tpl} ...")

    # backup
    backup = tpl.with_suffix(tpl.suffix + f".bak_add_charts_{ts}")
    backup.write_text(text, encoding="utf-8")
    print(f"  [BACKUP] -> {backup}")

    # thay thế lần đầu block KPI
    pattern = r'[ \t]*<script src="/static/js/vsp_dashboard_kpi_v1.js"></script>'
    m = re.search(pattern, text)
    if not m:
        print(f"  [WARN] Không tìm thấy script KPI chuẩn trong {tpl}, bỏ qua.")
        continue

    new_text = text[:m.start()] + block + text[m.end():]
    tpl.write_text(new_text, encoding="utf-8")
    print(f"  [OK] Đã chèn Chart.js + vsp_dashboard_charts_v1.js vào {tpl}")
PY
