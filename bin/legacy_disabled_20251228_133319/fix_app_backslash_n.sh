#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy app.py"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

lines = text.splitlines()
# Bỏ những dòng chỉ có '\n' (không nằm trong chuỗi)
fixed = [
    ln for ln in lines
    if not re.fullmatch(r"\s*\\n\s*", ln)
]

path.write_text("\n".join(fixed) + "\n", encoding="utf-8")
print("[OK] Đã loại bỏ các dòng rác '\\n' trong app.py")
PY
