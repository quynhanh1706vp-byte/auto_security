#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$ROOT/ui/templates/anyurl_dashboard.html"

echo "[i] Patching UI test table..."
cp "$TPL" "$TPL.bak_$(date +%Y%m%d_%H%M%S)"

python3 - << 'PY'
import pathlib, re

# Path
root = pathlib.Path(__file__).resolve().parents[1]
tpl = root / "ui/templates/anyurl_dashboard.html"

html = tpl.read_text(encoding="utf-8")

# --- Replace TEST TABLE block ---
pattern = re.compile(
    r"<table[\s\S]*?</table>",
    re.MULTILINE
)

replacement = """
<table class="sb-table sb-table-full">
    <thead>
        <tr>
            <th style="width: 80px;">ID</th>
            <th style="width: 140px;">Nhóm</th>
            <th style="width: 240px;">Mô tả Test Case</th>
            <th style="width: 300px;">Bước thực hiện</th>
            <th style="width: 260px;">Kết quả mong đợi</th>
            <th style="width: 120px;">Trạng thái</th>
            <th style="width: 160px;">Ghi chú</th>
        </tr>
    </thead>
    <tbody id="ui-test-table">
        <!-- filled by JS -->
    </tbody>
</table>
"""

new_html = re.sub(pattern, replacement, html, count=1)

tpl.write_text(new_html, encoding="utf-8")
print("[OK] Updated anyurl_dashboard.html")
PY

echo "[OK] Patch completed."
