#!/usr/bin/env bash
set -e

APP="app.py"
cp "$APP" "${APP}.bak_root_force_$(date +%Y%m%d_%H%M%S)"

python3 - "$APP" << 'PY'
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# Regex: bắt block route "/" hiện tại và thay luôn toàn bộ
pattern = r'@app\\.route\\("/")\\s*def\\s+[A-Za-z0-9_]+\\s*\\([^)]*\\):[\\s\\S]*?(?=\\n@app\\.route|\\Z)'

replacement = '''@app.route("/")
def index_ui5():
    \"\"\"Root redirect sang UI 5 tab mới.\"\"\"
    return redirect("/ui5")

'''

new_text, n = re.subn(pattern, replacement, text, count=1)

if n == 0:
    print("[WARN] Không tìm thấy block route('/') để thay. Sẽ chèn thêm route mới ở cuối file.")
    append_block = '''

@app.route("/")
def index_ui5():
    \"\"\"Root redirect sang UI 5 tab mới.\"\"\"
    return redirect("/ui5")
'''
    new_text = text + append_block
else:
    print("[OK] Đã thay route '/' hiện tại bằng redirect('/ui5').")

path.write_text(new_text, encoding="utf-8")
PY
