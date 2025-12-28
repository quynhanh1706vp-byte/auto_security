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

snippet = """
/* === SIDEBAR – RESET TO DASHBOARD-LIKE STYLE (CANONICAL) === */

/* Brand title: SECURITY BUNDLE màu xanh lá */
.sb-sidebar .sb-brand-title,
.sb-sidebar .sb-logo-title,
.sb-sidebar .sb-header h1,
.sb-sidebar .sb-header h2 {
  color: #8BC34A !important;
}

/* Gỡ mọi border / outline / shadow / pseudo của nav-item */
.sb-sidebar .nav-item,
.sb-sidebar .nav-item a {
  border: none !important;
  outline: none !important;
  box-shadow: none !important;
}

.sb-sidebar .nav-item::before,
.sb-sidebar .nav-item::after,
.sb-sidebar .nav-item.active::before,
.sb-sidebar .nav-item.active::after {
  content: none !important;
  border: 0 !important;
  box-shadow: none !important;
}

/* Non-active: nền trong suốt, chữ xanh lá */
.sb-sidebar .nav-item:not(.active) {
  background: transparent !important;
}

.sb-sidebar .nav-item:not(.active) a {
  display: block;
  padding: 8px 18px;
  background: transparent !important;
  color: #8BC34A !important;
  text-decoration: none;
}

/* Active: block xanh lá nguyên khối */
.sb-sidebar .nav-item.active a {
  display: block;
  padding: 8px 18px;
  background: #8BC34A !important;
  color: #061016 !important;
}

/* Tắt focus ring của browser trong sidebar */
.sb-sidebar .nav-item a:focus,
.sb-sidebar .nav-item a:focus-visible,
.sb-sidebar .nav-item a:active {
  outline: none !important;
  box-shadow: none !important;
}
"""

if "/* === SIDEBAR – RESET TO DASHBOARD-LIKE STYLE (CANONICAL) === */" not in text:
    text = text.rstrip() + "\\n" + snippet + "\\n"
    css_path.write_text(text, encoding="utf-8")
    print("[OK] Đã append block CSS sidebar canonical.")
else:
    print("[INFO] Block CSS sidebar canonical đã tồn tại, không thêm nữa.")
PY

echo "[DONE] patch_sidebar_reset_like_dashboard_v1.sh hoàn thành."
