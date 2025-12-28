#!/usr/bin/env bash
set -e

APP="app.py"
cp "$APP" "${APP}.bak_root2ui5_$(date +%Y%m%d_%H%M%S)"

python3 - "$APP" << 'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# Nếu đã trỏ sang /ui5 rồi thì thôi
if 'redirect("/ui5")' in text:
    print("[i] Root đã redirect sang /ui5, không cần sửa.")
    sys.exit(0)

old = 'return redirect("/v2")'
new = 'return redirect("/ui5")'

if old not in text:
    print("[WARN] Không tìm thấy dòng:", old)
else:
    text = text.replace(old, new, 1)
    path.write_text(text, encoding="utf-8")
    print("[OK] Đã đổi root redirect(/v2) -> redirect(/ui5).")
PY
