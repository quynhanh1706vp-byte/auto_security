#!/usr/bin/env bash
set -euo pipefail

APP="app.py"

python3 - "$APP" << 'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

old = 'return redirect("/v2")\\n\\n'
new = 'return redirect("/v2")'

if old not in data:
    print("[i] Không thấy chuỗi lỗi, có thể đã được sửa trước đó.")
else:
    data = data.replace(old, new)
    path.write_text(data, encoding="utf-8")
    print("[OK] Đã sửa dòng redirect(\"/v2\") bị dính \\n\\n.")

PY
