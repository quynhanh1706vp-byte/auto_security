#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
BASE="$ROOT/templates/base.html"

echo "[i] ROOT = $ROOT"
echo "[i] BASE = $BASE"

if [ ! -f "$BASE" ]; then
  echo "[ERR] Không tìm thấy templates/base.html"
  exit 1
fi

python3 - "$BASE" <<'PY'
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
html = path.read_text()

# 1) Lấy class chuẩn từ link Dashboard
m_dash = re.search(r'<a([^>]*)>\\s*Dashboard\\s*</a>', html, re.IGNORECASE)
if not m_dash:
    print("[ERR] Không tìm thấy link Dashboard trong base.html – không dám patch.")
    sys.exit(1)

dash_attrs = m_dash.group(1)
m_class = re.search(r'class="([^"]*)"', dash_attrs)
if not m_class:
    print("[ERR] Link Dashboard không có class=... – không dám patch.")
    sys.exit(1)

dash_class = m_class.group(1)
print("[i] Dashboard class =", dash_class)

def patch_label(label: str, html_src: str) -> str:
    pat = re.compile(r'<a([^>]*)>\\s*' + re.escape(label) + r'\\s*</a>', re.IGNORECASE)

    def repl(m):
        attrs = m.group(1)
        if 'class="' in attrs:
            attrs_new = re.sub(r'class="[^"]*"', f'class="{dash_class}"', attrs)
        else:
            attrs_new = attrs + f' class="{dash_class}"'
        new_tag = '<a' + attrs_new + '>' + label + '</a>'
        print(f"[OK] Patch class cho link {label}")
        return new_tag

    new_html, n = pat.subn(repl, html_src, count=1)
    if n == 0:
        print(f"[WARN] Không tìm thấy link {label}, bỏ qua.")
    return new_html

html_new = html
html_new = patch_label("Settings", html_new)
html_new = patch_label("Data Source", html_new)

if html_new != html:
    path.write_text(html_new)
    print("[DONE] Đã đồng bộ class Dashboard cho Settings + Data Source.")
else:
    print("[WARN] Không có thay đổi nào (có thể không tìm thấy Settings/Data Source).")
PY

echo "[DONE] patch_sidebar_use_dashboard_classes.sh hoàn thành."
