#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re

root = Path("/home/test/Data/SECURITY_BUNDLE/ui/static/css")
candidates = [
    root / "security_reslite.css",
    root / "security_resilient.css",
]

css_path = None
for p in candidates:
    if p.exists():
        css_path = p
        break

if css_path is None:
    print("[ERR] Không tìm thấy security_reslite.css hoặc security_resilient.css trong static/css/")
    raise SystemExit(1)

print(f"[i] Dùng CSS: {css_path}")

text = css_path.read_text(encoding="utf-8")
orig = text

# 1) Bỏ các block TOOL RULES cũ (nếu có)
text, n = re.subn(r"/\* === TOOL RULES PAGE.*?$", "", text, flags=re.S)
if n:
    print(f"[OK] Đã xoá {n} block CSS TOOL RULES PAGE cũ.")

# 2) Thêm block mới – palette giống Dashboard (PRIMARY = #8BC34A)
snippet = """
/* === TOOL RULES PAGE – SYNC WITH DASHBOARD === */
.tool-rules-section .sb-card {
  max-width: 1120px;
  margin: 16px auto 48px auto;
}

.tool-rules-section .sb-card-header {
  background: rgba(0, 0, 0, 0.7);
  border-bottom: 1px solid rgba(139, 195, 74, 0.40);
}

.tool-rules-section .sb-card-title {
  color: #e6fff7;
  letter-spacing: .03em;
}

.tool-rules-section .sb-card-subtitle {
  color: rgba(255, 255, 255, 0.70);
}

/* bảng rule: nền tối + hover xanh nhẹ giống Dashboard */
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
  background: rgba(139, 195, 74, 0.18);
}

/* input/select dark + viền xanh giống Dashboard (PRIMARY #8BC34A) */
.tool-rules-section .sb-input,
.tool-rules-section select.sb-input {
  background: rgba(3, 10, 18, 0.95);
  border-color: rgba(139, 195, 74, 0.45);
  color: #f8fffb;
}

.tool-rules-section .sb-input:focus,
.tool-rules-section select.sb-input:focus {
  border-color: rgba(139, 195, 74, 0.90);
  box-shadow: 0 0 0 1px rgba(139, 195, 74, 0.55);
}

/* checkbox Enabled gọn hơn chút */
.tool-rules-section td input[type="checkbox"] {
  transform: scale(0.95);
}

/* nút Add / Reload / Save spacing gần giống Run scan */
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

echo "[DONE] patch_tool_rules_css_sync_dashboard_v2.sh hoàn thành."
