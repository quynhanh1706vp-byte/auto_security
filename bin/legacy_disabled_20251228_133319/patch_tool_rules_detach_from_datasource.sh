#!/usr/bin/env bash
set -euo pipefail

TPL="/home/test/Data/SECURITY_BUNDLE/ui/templates/datasource.html"

python3 - <<'PY'
from pathlib import Path

tpl_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates/datasource.html")
html = tpl_path.read_text(encoding="utf-8")
orig = html

# Ưu tiên bản đã có class tool-rules-section
pattern1 = '<div class="sb-section tool-rules-section" style="margin-top: 32px;">'
replace1 = '<div class="sb-section tool-rules-section" style="margin-top: 32px; {% if active_page != \'tool_rules\' %}display:none;{% endif %}">'

if "tool-rules-section" in html and "display:none" not in html:
    if pattern1 in html:
        html = html.replace(pattern1, replace1, 1)
        print("[OK] Đã thêm guard active_page cho tool-rules-section (hide ở Data Source).")
    else:
        print("[WARN] Có tool-rules-section nhưng không match được pattern style mặc định.")
else:
    # Fallback: trường hợp chưa có class tool-rules-section, dùng pattern gốc
    pattern2 = '<div class="sb-section" style="margin-top: 32px;">'
    replace2 = '<div class="sb-section" style="margin-top: 32px; {% if active_page != \'tool_rules\' %}display:none;{% endif %}">'
    if "display:none" not in html and pattern2 in html:
        html = html.replace(pattern2, replace2, 1)
        print("[OK] Đã thêm guard active_page cho sb-section Tool rules (fallback).")
    else:
        print("[INFO] Không cần hoặc không tìm thấy block Tool rules để sửa.")

if html != orig:
    tpl_path.write_text(html, encoding="utf-8")
PY

echo "[DONE] patch_tool_rules_detach_from_datasource.sh hoàn thành."
