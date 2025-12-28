#!/usr/bin/env bash
set -e

APP="app.py"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không thấy $APP trong thư mục hiện tại."
  exit 1
fi

cp "$APP" "${APP}.bak_stray_$(date +%Y%m%d_%H%M%S)"

python3 - "$APP" << 'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

lines = text.splitlines()

# Bỏ mọi dòng chỉ chứa "\n" (kể cả có space/tab xung quanh)
new_lines = [ln for ln in lines if ln.strip() != r"\n"]

if len(new_lines) == len(lines):
    print("[i] Không tìm thấy dòng '\\n' đơn lẻ để xoá.")
else:
    removed = len(lines) - len(new_lines)
    print(f"[OK] Đã xoá {removed} dòng '\\\\n' rác.")

path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
PY
