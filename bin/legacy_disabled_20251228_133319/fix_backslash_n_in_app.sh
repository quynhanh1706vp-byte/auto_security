#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

lines = text.splitlines()
new_lines = []
removed = 0

for ln in lines:
    # Loại bỏ các dòng chỉ chứa "\n" (có thể có thêm space/tab)
    if ln.strip() == r'\n':
        removed += 1
        continue
    new_lines.append(ln)

path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
print(f"[OK] Đã xoá {removed} dòng '\\n' rác trong app.py")
PY
