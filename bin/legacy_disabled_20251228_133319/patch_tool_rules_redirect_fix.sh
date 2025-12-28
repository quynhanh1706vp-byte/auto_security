#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/app.py"

python3 - <<'PY'
from pathlib import Path
import re

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/app.py")
text = app_path.read_text(encoding="utf-8")
orig = text

pattern = re.compile(
    r'@app\.route\("/tool_rules", methods=\["GET"\]\)\s+'
    r'def tool_rules_redirect\([^)]*\):\s+'
    r'(?:.*\n)+?',   # body cũ bất kỳ
    flags=re.MULTILINE
)

new_block = '''
@app.route("/tool_rules", methods=["GET"])
def tool_rules_redirect():
    from flask import redirect
    # redirect thẳng sang path /datasource (không dùng endpoint name)
    return redirect("/datasource")
'''

if "@app.route(\"/tool_rules\", methods=[\"GET\"])" not in text:
    print("[WARN] Không thấy route /tool_rules trong app.py – không sửa gì.")
else:
    if pattern.search(text):
        text = pattern.sub(new_block + "\n", text, count=1)
        print("[OK] Đã thay body tool_rules_redirect() dùng redirect('/datasource').")
    else:
        # fallback: chèn block mới (phòng khi regex không match)
        text += "\n" + new_block + "\n"
        print("[WARN] Không match được block cũ, đã append block mới ở cuối file.")

    app_path.write_text(text, encoding="utf-8")

PY

# kiểm tra cú pháp
python3 -m py_compile "$APP" && echo "[OK] app.py compile ok"

echo "[DONE] patch_tool_rules_redirect_fix.sh hoàn thành."
