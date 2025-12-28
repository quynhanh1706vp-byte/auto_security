#!/usr/bin/env bash
set -euo pipefail

TPL="templates/index.html"
echo "[i] TPL = $TPL"

[ -f "$TPL" ] || { echo "[ERR] Không tìm thấy $TPL"; exit 1; }

python3 - "$TPL" <<'PY'
import sys

path = sys.argv[1]
html = open(path, "r", encoding="utf-8").read()

nav_start = html.find('<nav class="sb-nav">')
if nav_start == -1:
    print("[ERR] Không tìm thấy <nav class=\"sb-nav\">")
    sys.exit(1)
nav_end = html.find("</nav>", nav_start)
if nav_end == -1:
    print("[ERR] Không tìm thấy </nav>")
    sys.exit(1)
nav_end += len("</nav>")

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

old_nav = html[nav_start:nav_end]
html = html.replace(old_nav, new_nav)

open(path, "w", encoding="utf-8").write(html)
print("[OK] Đã patch nav thành <a href='...'> (clickable).")
PY
