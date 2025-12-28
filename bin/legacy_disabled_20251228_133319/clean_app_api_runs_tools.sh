#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
lines = text.splitlines(keepends=True)

out = []
in_patch = False
removed = 0

for line in lines:
    if "=== AUTO PATCH: API runs_brief + tools_by_config ===" in line:
        in_patch = True
        removed += 1
        continue
    if in_patch:
        removed += 1
        if "=== END AUTO PATCH ===" in line:
            in_patch = False
        continue
    out.append(line)

new_text = "".join(out)
path.write_text(new_text, encoding="utf-8")
print(f"[OK] Đã xoá {removed} dòng AUTO PATCH (runs_brief/tools_by_config) khỏi {path}")
PY
