#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

python3 - <<'PY'
from pathlib import Path

path = Path("app.py")
text = path.read_text(encoding="utf-8")
lines = text.splitlines()

# tìm tất cả decorator @app.route(.../runs...) mà ngay sau là def runs_page(...)
idxs = []
for i, line in enumerate(lines):
    if "@app.route(" in line and "/runs" in line:
        if i + 1 < len(lines) and "def runs_page" in lines[i+1]:
            idxs.append(i)

print(f"[INFO] found {len(idxs)} @app.route(.../runs...) for runs_page")

if len(idxs) <= 1:
    print("[INFO] Không có route trùng, không cần sửa.")
else:
    # GIỮ LẠI decorator CUỐI CÙNG (thường là bản mới nhất),
    # comment hết mấy cái trước đó.
    for i in idxs[:-1]:
        if not lines[i].lstrip().startswith("#"):
            lines[i] = "# " + lines[i] + "  # disabled duplicate /runs route"
            print(f"[INFO] Commented old /runs decorator at line {i+1}")

new_text = "\n".join(lines)
path.write_text(new_text, encoding="utf-8")
print("[OK] Đã giữ lại đúng 1 decorator /runs cho runs_page.")
PY
