#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"

echo "[PATCH] Dọn import 'from flask import request, Response' (giữ đúng 1 bản top-level) trong $APP"

python - << 'PY'
from pathlib import Path

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
txt = app_path.read_text(encoding="utf-8")
lines = txt.splitlines()

new_lines = []
seen = False

for line in lines:
    if "from flask import request, Response" in line:
        if not seen:
            # Giữ lại đúng 1 dòng, KHÔNG thụt lề
            new_lines.append("from flask import request, Response")
            seen = True
        else:
            # Bỏ hết các bản trùng / lệch chỗ
            print("[PATCH] Remove duplicate/indented line:", line.strip())
            continue
    else:
        new_lines.append(line)

new_txt = "\n".join(new_lines) + "\n"
app_path.write_text(new_txt, encoding="utf-8")
print("[OK] Đã ghi lại", app_path)
PY

echo "[PATCH] Done."
