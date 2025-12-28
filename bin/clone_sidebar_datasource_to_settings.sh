#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re

root = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates")
src  = root / "datasource.html"
dst  = root / "settings.html"

if not src.exists():
    print("[ERR] Không tìm thấy datasource.html")
    raise SystemExit(1)
if not dst.exists():
    print("[ERR] Không tìm thấy settings.html")
    raise SystemExit(1)

src_text = src.read_text(encoding="utf-8")
dst_text = dst.read_text(encoding="utf-8")

# Lấy block sidebar trong datasource: từ <div class="sb-sidebar"> đến ngay trước <div class="sb-main">
m_src = re.search(r'(<div class="sb-sidebar"[\\s\\S]*?)<div class="sb-main">', src_text)
if not m_src:
    print("[ERR] Không tìm được sb-sidebar trong datasource.html")
    raise SystemExit(1)
sidebar_block = m_src.group(1)
print("[i] Đã lấy sidebar từ datasource.html (đã có Rule overrides).")

# Tìm block sidebar tương ứng trong settings
m_dst = re.search(r'(<div class="sb-sidebar"[\\s\\S]*?)<div class="sb-main">', dst_text)
if not m_dst:
    print("[ERR] Không tìm được sb-sidebar trong settings.html")
    raise SystemExit(1)

old_block = m_dst.group(1)
new_dst_text = dst_text.replace(old_block, sidebar_block)

if new_dst_text == dst_text:
    print("[WARN] Không có thay đổi nào trong settings.html.")
else:
    dst.write_text(new_dst_text, encoding="utf-8")
    print("[OK] Đã clone sidebar từ datasource.html sang settings.html")

PY

echo "[DONE] clone_sidebar_datasource_to_settings.sh hoàn thành."
