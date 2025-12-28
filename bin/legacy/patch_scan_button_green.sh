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

# Màu tím-hồng cũ (do mình patch lần trước)
old_bg = "background: linear-gradient(90deg,#6366f1,#ec4899);"
old_shadow = "box-shadow: 0 12px 30px rgba(88,80,236,0.55);"

# Màu xanh kiểu RUN ANY-URL (xanh lá tươi, hơi gradient nhẹ)
new_bg = "background: linear-gradient(90deg,#22c55e,#86efac);"
new_shadow = "box-shadow: 0 12px 30px rgba(34,197,94,0.55);"

changed = False
if old_bg in html:
    html = html.replace(old_bg, new_bg)
    changed = True
if old_shadow in html:
    html = html.replace(old_shadow, new_shadow)
    changed = True

# Nếu không tìm thấy tím-hồng thì thử đổi trực tiếp trong block .scan-btn
if not changed and ".scan-btn" in html:
    html = html.replace(
        "background: radial-gradient(circle at top left,#22c55e,#a3e635);",
        new_bg
    )
    html = html.replace(
        "box-shadow: 0 12px 30px rgba(22,163,74,0.55);",
        new_shadow
    )
    changed = True

print("[OK] Đã đổi màu scan-btn sang xanh ANY-URL." if changed else
      "[WARN] Không tìm được đoạn background cũ để thay.")

path.write_text(html, encoding="utf-8")
PY
