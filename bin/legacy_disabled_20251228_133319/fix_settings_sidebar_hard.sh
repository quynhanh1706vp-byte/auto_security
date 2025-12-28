#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re

path = Path("templates/settings.html")
if not path.exists():
    print("[ERR] Không tìm thấy templates/settings.html")
    raise SystemExit(1)

text = path.read_text(encoding="utf-8")
orig = text

# Tìm nguyên block <nav class="sb-nav"> ... </nav>
m = re.search(r'(<nav class="sb-nav"[\\s\\S]*?</nav>)', text)
if not m:
    print("[ERR] Không tìm thấy <nav class=\"sb-nav\"> trong settings.html")
    raise SystemExit(1)

new_nav = """<nav class="sb-nav">
          <div class="nav-item"><a href="/">Dashboard</a></div>
          <div class="nav-item"><a href="/runs">Run &amp; Report</a></div>
          <div class="nav-item"><a href="/settings">Settings</a></div>
          <div class="nav-item"><a href="/datasource">Data Source</a></div>
          <div class="nav-item"><a href="/tool_rules">Rule overrides</a></div>
        </nav>"""

start, end = m.span()
text = text[:start] + new_nav + text[end:]

if text != orig:
    path.write_text(text, encoding="utf-8")
    print("[OK] Đã ghi đè sidebar nav trong settings.html với 5 tab.")
else:
    print("[INFO] Không có thay đổi (nội dung giống cũ).")
PY

echo "[DONE] fix_settings_sidebar_hard.sh hoàn thành."
