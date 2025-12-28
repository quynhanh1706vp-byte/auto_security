#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re

root_ui = Path("/home/test/Data/SECURITY_BUNDLE/ui")

# ==== 1) Auto-chọn file CSS (reslite hoặc resilient) ====
css_root = root_ui / "static" / "css"
candidates = [
    css_root / "security_reslite.css",
    css_root / "security_resilient.css",
]
css_path = None
for p in candidates:
    if p.exists():
        css_path = p
        break

if css_path is None:
    print("[ERR] Không tìm thấy CSS security_reslite.css hoặc security_resilient.css trong static/css/")
    raise SystemExit(1)

print(f"[i] Dùng CSS: {css_path}")
css = css_path.read_text(encoding="utf-8")
orig_css = css

# helper xoá block theo tiêu đề
def remove_block(text: str, marker: str) -> str:
    pat = r"/\* === " + re.escape(marker) + r" === \*/[\s\S]*?(?=/\* ===|$)"
    new, n = re.subn(pat, "", text)
    if n:
        print(f"[OK] Đã xoá {n} block '{marker}' cũ.")
    return new

css = remove_block(css, "TOOL RULES PAGE – SYNC WITH DASHBOARD")
css = remove_block(css, "SETTINGS PAGE – SYNC WITH DASHBOARD")

# ==== 2) Thêm block mới cho TOOL RULES + SETTINGS (full hơn, đồng bộ Dashboard) ====
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

if "/* === TOOL RULES PAGE – SYNC WITH DASHBOARD === */" not in css:
    css = css.rstrip() + "\n" + snippet + "\n"
    css_path.write_text(css, encoding="utf-8")
    print("[OK] Đã append block CSS TOOL RULES + SETTINGS SYNC.")
else:
    print("[INFO] Block CSS sync đã tồn tại, không ghi đè.")

# ==== 3) Gắn class settings-section cho section chính của trang Settings ====
tpl_settings = root_ui / "templates" / "settings.html"
if tpl_settings.exists():
    html = tpl_settings.read_text(encoding="utf-8")
    orig_html = html
    if "settings-section" in html:
        print("[INFO] settings.html đã có settings-section, bỏ qua.")
    else:
        # chỉ sửa match đầu tiên của sb-section
        new_html = html.replace('class="sb-section', 'class="sb-section settings-section', 1)
        if new_html != html:
            tpl_settings.write_text(new_html, encoding="utf-8")
            print("[OK] Đã gắn class settings-section cho sb-section đầu tiên trong settings.html.")
        else:
            print("[WARN] Không tìm thấy class=\"sb-section\" trong settings.html.")
else:
    print("[WARN] Không tìm thấy templates/settings.html để patch.")

PY

echo "[DONE] patch_ui_settings_and_toolrules_fullwidth.sh hoàn thành."
