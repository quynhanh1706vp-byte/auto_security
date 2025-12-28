#!/usr/bin/env bash
set -euo pipefail

CSS="/home/test/Data/SECURITY_BUNDLE/ui/static/css/security_reslite.css"
echo "[i] CSS = $CSS"

python3 - <<'PY'
from pathlib import Path
import re

css_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/static/css/security_reslite.css")
text = css_path.read_text(encoding="utf-8")
orig = text

# 1) Bỏ block TOOL RULES cũ (nếu có)
text, n = re.subn(r"/\* === TOOL RULES PAGE.*?$", "", text, flags=re.S)
if n:
    print(f"[OK] Đã xoá {n} block CSS TOOL RULES PAGE cũ.")

# 2) Thêm block mới – dùng palette giống Dashboard
snippet = """
/* === TOOL RULES PAGE – SYNC WITH DASHBOARD === */
.tool-rules-section .sb-card {
  max-width: 1120px;
  margin: 16px auto 48px auto;
}

.tool-rules-section .sb-card-header {
  /* giống tone các card khác: nền tối + viền xanh nhẹ */
  background: rgba(0, 0, 0, 0.7);
  border-bottom: 1px solid rgba(0, 255, 153, 0.35);
}

.tool-rules-section .sb-card-title {
  color: #e6fff7;
  letter-spacing: .03em;
}

.tool-rules-section .sb-card-subtitle {
  color: rgba(255, 255, 255, 0.70);
}

/* bảng rule: nền tối, hover xanh nhẹ giống theme */
.tool-rules-section .sb-table thead th {
  background: rgba(0, 0, 0, 0.6);
}

.tool-rules-section .sb-table tbody tr:nth-child(odd) {
  background: rgba(0, 0, 0, 0.48);
}

.tool-rules-section .sb-table tbody tr:nth-child(even) {
  background: rgba(0, 0, 0, 0.38);
}

.tool-rules-section .sb-table tbody tr:hover {
  background: rgba(0, 255, 153, 0.12);
}

/* input/select đúng style dark + viền xanh như Dashboard */
.tool-rules-section .sb-input,
.tool-rules-section select.sb-input {
  background: rgba(3, 10, 18, 0.95);
  border-color: rgba(0, 255, 153, 0.45);
  color: #f8fffb;
}

.tool-rules-section .sb-input:focus,
.tool-rules-section select.sb-input:focus {
  border-color: rgba(0, 255, 153, 0.9);
  box-shadow: 0 0 0 1px rgba(0, 255, 153, 0.5);
}

/* checkbox Enabled cho gọn */
.tool-rules-section td input[type="checkbox"] {
  transform: scale(0.95);
}

/* nút Add / Reload / Save: khoảng cách giống Run scan */
.tool-rules-section .sb-card-actions .sb-btn {
  margin-left: 8px;
}
"""

if "/* === TOOL RULES PAGE – SYNC WITH DASHBOARD === */" not in text:
    text = text.rstrip() + "\n" + snippet + "\n"
    css_path.write_text(text, encoding="utf-8")
    print("[OK] Đã append block CSS TOOL RULES PAGE – SYNC WITH DASHBOARD.")
else:
    print("[INFO] Block CSS TOOL RULES PAGE – SYNC WITH DASHBOARD đã tồn tại, không thêm nữa.")
PY

echo "[DONE] patch_tool_rules_css_sync_dashboard.sh hoàn thành."
