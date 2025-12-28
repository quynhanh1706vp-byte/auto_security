#!/usr/bin/env bash
set -e
cd /home/test/Data/SECURITY_BUNDLE/ui

if [ ! -f app.py ]; then
  echo "[ERR] Không tìm thấy app.py trong ui/"
  exit 1
fi

echo "[i] Các template Flask đang dùng trong app.py:"
python3 - <<'PY'
import io, re

text = io.open("app.py", "r", encoding="utf-8").read()
seen = set()
for m in re.finditer(r"render_template\(\s*['\"]([^'\"]+)['\"]", text):
    name = m.group(1)
    if name not in seen:
        seen.add(name)
        print(" -", name)
PY
