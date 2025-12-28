#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re

root_ui = Path("/home/test/Data/SECURITY_BUNDLE/ui")
css_root = root_ui / "static" / "css"

# Tìm đúng file CSS đang dùng, ví dụ: security_reslite_nt.css
cands = sorted(css_root.glob("security_resli*.css"))
if not cands:
    print("[ERR] Không tìm thấy security_resli*.css trong static/css/")
    raise SystemExit(1)

css_path = cands[0]
print(f"[i] Dùng CSS: {css_path}")

css = css_path.read_text(encoding="utf-8")
orig = css

# 1) Bỏ TẤT CẢ block TOOL RULES / SETTINGS mình đã thêm trước đó
def remove_block(text: str, marker: str) -> str:
    pat = r"/\* === " + re.escape(marker) + r".*?=== \*/[\s\S]*?(?=/\* ===|$)"
    new, n = re.subn(pat, "", text)
    if n:
        print(f"[OK] Đã xoá {n} block '{marker}' cũ.")
    return new

css = remove_block(css, "TOOL RULES PAGE")
css = remove_block(css, "SETTINGS PAGE")
css = remove_block(css, "TOOL RULES PAGE – SYNC WITH DASHBOARD")
css = remove_block(css, "SETTINGS PAGE – SYNC WITH DASHBOARD")
css = remove_block(css, "TOOL RULES PAGE – SYNC WITH DASHBOARD (FINAL)")
css = remove_block(css, "SETTINGS PAGE – SYNC WITH DASHBOARD (FINAL)")

# 2) Thêm block mới: chỉ chỉnh layout, KHÔNG chỉnh màu
snippet = """
/* === SETTINGS & TOOL RULES – LAYOUT ONLY (no color override) === */
.settings-section .sb-card,
.tool-rules-section .sb-card {
  width: 100%;
  max-width: 1280px;
  margin: 16px auto 48px auto;
}
"""

if "SETTINGS & TOOL RULES – LAYOUT ONLY" not in css:
    css = css.rstrip() + "\\n" + snippet + "\\n"
    print("[OK] Đã append block layout-only cho Settings & Tool rules.")
else:
    print("[INFO] Block layout-only đã tồn tại, giữ nguyên.")

css_path.write_text(css, encoding="utf-8")
print("[DONE] Đã ghi lại", css_path.name)
PY

echo "[DONE] patch_settings_colors_reset.sh hoàn thành."
