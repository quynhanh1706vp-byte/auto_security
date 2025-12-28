#!/usr/bin/env bash
set -euo pipefail

HTML="SECURITY_BUNDLE_FULL_5_PAGES.html"

if [ ! -f "$HTML" ]; then
  echo "[ERR] Không tìm thấy $HTML ở $(pwd)"
  exit 1
fi

python - <<'PY'
from pathlib import Path

p = Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
text = p.read_text(encoding="utf-8")

# 1) BỎ link tới security_bundle_fullscreen_override.css (nếu có)
lines = text.splitlines()
new_lines = []
for line in lines:
    if "security_bundle_fullscreen_override.css" in line:
        # bỏ dòng này
        continue
    new_lines.append(line)

text = "\n".join(new_lines)

# 2) THÊM một style rất nhẹ chỉ để chặn tràn ngang
marker = "</head>"
style_block = """  <style>
    /* SB_LAYOUT_FIX */
    html, body { overflow-x: hidden; }
  </style>
"""

if "/* SB_LAYOUT_FIX */" not in text:
    if marker in text:
        text = text.replace(marker, style_block + "\n" + marker)
    else:
        text = style_block + "\n" + text

p.write_text(text, encoding="utf-8")
print("[OK] Đã reset layout + chèn fix overflow-x.")
PY

# 3) Xoá luôn file CSS override cũ (nếu còn)
rm -f static/css/security_bundle_fullscreen_override.css || true

echo "[DONE] fix_dashboard_layout_reset.sh hoàn tất."
