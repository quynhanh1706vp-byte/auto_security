#!/usr/bin/env bash
set -euo pipefail

TPL="templates/index.html"
echo "[i] TPL = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
html = path.read_text(encoding="utf-8")

old_bg = "background: radial-gradient(circle at top left,#22c55e,#a3e635);"
old_shadow = "box-shadow: 0 12px 30px rgba(22,163,74,0.55);"

new_bg = "background: linear-gradient(90deg,#6366f1,#ec4899);"
new_shadow = "box-shadow: 0 12px 30px rgba(88,80,236,0.55);"

changed = False
if old_bg in html:
    html = html.replace(old_bg, new_bg)
    changed = True
if old_shadow in html:
    html = html.replace(old_shadow, new_shadow)
    changed = True

if changed:
    print("[OK] Đã đổi màu nút Run scan sang tím-hồng gradient.")
else:
    print("[WARN] Không tìm thấy đoạn CSS cũ của .scan-btn – có thể đã được sửa trước đó.")

path.write_text(html, encoding="utf-8")
PY
