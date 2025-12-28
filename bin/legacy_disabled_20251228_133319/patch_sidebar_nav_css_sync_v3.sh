#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path

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

# Append block mới để ép lại màu sidebar
snippet = """
/* === SIDEBAR NAV – SYNC ALL TABS WITH DASHBOARD === */
/* Non-active items: nền trong suốt, chữ xanh lá nhẹ */
.sb-sidebar .nav-item:not(.active) {
  background: transparent !important;
}

.sb-sidebar .nav-item:not(.active) a {
  background: transparent !important;
  color: #8BC34A !important;
}

/* Active item: block xanh lá (giống Dashboard) */
.sb-sidebar .nav-item.active {
  background: #8BC34A !important;
}

.sb-sidebar .nav-item.active a {
  color: #061016 !important;
}
"""

if "/* === SIDEBAR NAV – SYNC ALL TABS WITH DASHBOARD === */" not in text:
    text = text.rstrip() + "\\n" + snippet + "\\n"
    css_path.write_text(text, encoding="utf-8")
    print("[OK] Đã append block CSS SIDEBAR NAV – SYNC ALL TABS WITH DASHBOARD.")
else:
    print("[INFO] Block CSS SIDEBAR NAV – SYNC ALL TABS WITH DASHBOARD đã tồn tại, không thêm nữa.")
PY

echo "[DONE] patch_sidebar_nav_css_sync_v3.sh hoàn thành."
