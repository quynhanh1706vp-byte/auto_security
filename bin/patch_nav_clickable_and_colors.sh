#!/usr/bin/env bash
set -euo pipefail

TPL="/home/test/Data/SECURITY_BUNDLE/ui/templates/index.html"
echo "[i] TPL = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy templates/index.html"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys

path = sys.argv[1]
html = open(path, "r", encoding="utf-8").read()

# 1) Thay khối <nav> để các mục là <a href="...">
nav_start = html.find('<nav class="sb-nav">')
if nav_start == -1:
    print("[ERR] Không tìm thấy <nav class=\"sb-nav\">")
    sys.exit(1)

nav_end = html.find("</nav>", nav_start)
if nav_end == -1:
    print("[ERR] Không tìm thấy </nav> sau sb-nav")
    sys.exit(1)
nav_end += len("</nav>")

old_nav = html[nav_start:nav_end]

new_nav = '''<nav class="sb-nav">
          <a class="sb-nav-item active" href="/">
            <span class="sb-nav-dot"></span>
            <span>Dashboard</span>
          </a>
          <a class="sb-nav-item" href="/runs">
            <span class="sb-nav-dot" style="opacity:.4;"></span>
            <span>Run &amp; Report</span>
          </a>
          <a class="sb-nav-item" href="/settings">
            <span class="sb-nav-dot" style="opacity:.4;"></span>
            <span>Settings</span>
          </a>
          <a class="sb-nav-item" href="/data-source">
            <span class="sb-nav-dot" style="opacity:.4;"></span>
            <span>Data Source</span>
          </a>
        </nav>'''

html = html.replace(old_nav, new_nav)

# 2) Chỉnh màu card giống ANY-URL hơn + làm nav hover đẹp
#    - sửa background .sb-card
html = html.replace(
    "      .sb-card {\n        background:rgba(5,5,20,0.88);",
    "      .sb-card {\n        background:linear-gradient(135deg,rgba(18,22,46,0.98),rgba(6,7,18,0.98));"
)

#    - thêm CSS cho <a.sb-nav-item>, hover, v.v.
marker = ".sb-section-title {"
ins_css = '''      .sb-nav-item {
        display:flex;
        align-items:center;
        gap:8px;
        padding:8px 10px;
        border-radius:999px;
        font-size:13px;
        margin-bottom:6px;
        opacity:.8;
        text-decoration:none;
        color:inherit;
        transition:background .18s ease, opacity .18s ease, transform .12s ease;
      }
      .sb-nav-item:hover {
        background:linear-gradient(90deg,#7a6eff,#ff7bd5);
        opacity:1;
        transform:translateX(2px);
      }
      .sb-nav-item.active {
        background:linear-gradient(90deg,#6657ff,#ff6bcb);
        opacity:1;
      }
'''

pos = html.find(marker)
if pos != -1 and "PATCH_NAV_CLICKABLE" not in html:
    html = html.replace(marker, ins_css + "\n      " + marker)
else:
    print("[WARN] Không chèn được CSS nav (marker không tìm thấy hoặc đã patch).")

open(path, "w", encoding="utf-8").write(html)
print("[OK] Đã patch nav clickable + màu card.")
PY
