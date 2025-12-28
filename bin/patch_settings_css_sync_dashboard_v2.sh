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

# 1) Xoá block SETTINGS PAGE cũ (nếu có)
text, n = re.subn(r"/\* === SETTINGS PAGE – SYNC WITH DASHBOARD.*?$", "", text, flags=re.S)
if n:
    print(f"[OK] Đã xoá {n} block CSS SETTINGS PAGE cũ.")

snippet = """
/* === SETTINGS PAGE – SYNC WITH DASHBOARD === */
/* wrapper Settings: đặt class .settings-section trong templates/settings.html */
.settings-section .sb-card {
  max-width: 1120px;
  margin: 16px auto 48px auto;
}

.settings-section .sb-card-header {
  background: rgba(0, 0, 0, 0.7);
  border-bottom: 1px solid rgba(139, 195, 74, 0.40);
}

.settings-section .sb-card-title {
  color: #e6fff7;
  letter-spacing: .03em;
}

.settings-section .sb-card-subtitle {
  color: rgba(255, 255, 255, 0.70);
}

/* bảng tool_config editable */
.settings-section .sb-table thead th {
  background: rgba(0, 0, 0, 0.6);
}

.settings-section .sb-table tbody tr:nth-child(odd) {
  background: rgba(0, 0, 0, 0.48);
}

.settings-section .sb-table tbody tr:nth-child(even) {
  background: rgba(0, 0, 0, 0.38);
}

.settings-section .sb-table tbody tr:hover {
  background: rgba(139, 195, 74, 0.18);
}

/* input/select cho Settings */
.settings-section .sb-input,
.settings-section select.sb-input {
  background: rgba(3, 10, 18, 0.95);
  border-color: rgba(139, 195, 74, 0.45);
  color: #f8fffb;
}

.settings-section .sb-input:focus,
.settings-section select.sb-input:focus {
  border-color: rgba(139, 195, 74, 0.90);
  box-shadow: 0 0 0 1px rgba(139, 195, 74, 0.55);
}

/* dùng cho bảng nếu bạn không có .settings-section wrapper */
#tool-config-table thead th {
  background: rgba(0, 0, 0, 0.6);
}
#tool-config-table tbody tr:nth-child(odd) {
  background: rgba(0, 0, 0, 0.48);
}
#tool-config-table tbody tr:nth-child(even) {
  background: rgba(0, 0, 0, 0.38);
}
#tool-config-table tbody tr:hover {
  background: rgba(139, 195, 74, 0.18);
}
"""

if "/* === SETTINGS PAGE – SYNC WITH DASHBOARD === */" not in text:
    text = text.rstrip() + "\n" + snippet + "\n"
    css_path.write_text(text, encoding="utf-8")
    print("[OK] Đã append block CSS SETTINGS PAGE – SYNC WITH DASHBOARD.")
else:
    print("[INFO] Block CSS SETTINGS PAGE – SYNC WITH DASHBOARD đã tồn tại, không thêm nữa.")
PY

echo "[DONE] patch_settings_css_sync_dashboard_v2.sh hoàn thành."
