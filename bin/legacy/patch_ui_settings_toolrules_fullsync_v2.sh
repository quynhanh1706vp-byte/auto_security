#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re

root_ui = Path("/home/test/Data/SECURITY_BUNDLE/ui")

# ==== 1) Tìm đúng file CSS security_resli*.css ====
css_root = root_ui / "static" / "css"
candidates = sorted(css_root.glob("security_resli*.css"))
if not candidates:
    print("[ERR] Không tìm thấy security_resli*.css trong static/css/")
    raise SystemExit(1)

css_path = candidates[0]
print(f"[i] Dùng CSS: {css_path}")

css = css_path.read_text(encoding="utf-8")

def remove_block(text: str, marker_prefix: str) -> str:
    pat = r"/\* === " + re.escape(marker_prefix) + r".*?=== \*/[\s\S]*?(?=/\* ===|$)"
    new, n = re.subn(pat, "", text)
    if n:
        print(f"[OK] Đã xoá {n} block '{marker_prefix}...' cũ trong CSS.")
    return new

# Bỏ các block TOOL RULES / SETTINGS cũ nếu có
css = remove_block(css, "TOOL RULES PAGE")
css = remove_block(css, "SETTINGS PAGE")

snippet = """
/* === TOOL RULES PAGE – SYNC WITH DASHBOARD === */
.tool-rules-section .sb-card {
  max-width: 1280px;
  margin: 16px auto 48px auto;
}

.tool-rules-section .sb-card-header {
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

.tool-rules-section td input[type="checkbox"] {
  transform: scale(0.95);
}

.tool-rules-section .sb-card-actions .sb-btn {
  margin-left: 8px;
}

/* === SETTINGS PAGE – SYNC WITH DASHBOARD === */
.settings-section .sb-card {
  max-width: 1280px;
  margin: 16px auto 48px auto;
}

.settings-section .sb-card-header {
  background: rgba(0, 0, 0, 0.7);
  border-bottom: 1px solid rgba(0, 255, 153, 0.35);
}

.settings-section .sb-card-title {
  color: #e6fff7;
  letter-spacing: .03em;
}

.settings-section .sb-card-subtitle {
  color: rgba(255, 255, 255, 0.70);
}

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
  background: rgba(0, 255, 153, 0.12);
}

.settings-section .sb-input,
.settings-section select.sb-input {
  background: rgba(3, 10, 18, 0.95);
  border-color: rgba(0, 255, 153, 0.45);
  color: #f8fffb;
}

.settings-section .sb-input:focus,
.settings-section select.sb-input:focus {
  border-color: rgba(0, 255, 153, 0.9);
  box-shadow: 0 0 0 1px rgba(0, 255, 153, 0.5);
}
"""

css = css.rstrip() + "\n" + snippet + "\n"
css_path.write_text(css, encoding="utf-8")
print("[OK] Đã ghi block CSS sync cho TOOL RULES + SETTINGS vào", css_path.name)

# ==== 2) Patch settings.html: thêm settings-section + bỏ inline style sb-card ====
tpl_settings = root_ui / "templates" / "settings.html"
if not tpl_settings.exists():
    print("[WARN] Không tìm thấy templates/settings.html")
else:
    html = tpl_settings.read_text(encoding="utf-8")
    orig_html = html

    # Thêm settings-section vào mọi sb-section
    if 'settings-section' not in html:
        html = html.replace('class="sb-section', 'class="sb-section settings-section')
        print("[OK] Đã thêm settings-section vào tất cả sb-section trong settings.html.")
    else:
        print("[INFO] settings.html đã có settings-section, giữ nguyên.")

    # Bỏ inline style của sb-card (nếu có)
    # Ví dụ: <div class="sb-card" style="max-width: 960px; margin: 0 auto;">
    html_new = re.sub(
        r'<div\s+class="sb-card"[^>]*>',
        '<div class="sb-card">',
        html
    )
    if html_new != html:
        print("[OK] Đã remove inline style trong các sb-card của settings.html.")
        html = html_new

    if html != orig_html:
        tpl_settings.write_text(html, encoding="utf-8")
        print("[OK] Đã ghi lại templates/settings.html.")
    else:
        print("[INFO] Không cần thay đổi settings.html thêm.")
PY

echo "[DONE] patch_ui_settings_toolrules_fullsync_v2.sh hoàn thành."
