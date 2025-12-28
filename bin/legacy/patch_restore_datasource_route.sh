#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/app.py"

python3 - <<'PY'
from pathlib import Path
import re

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/app.py")
text = app_path.read_text(encoding="utf-8")
orig = text

if '@app.route("/datasource"' in text:
    print("[INFO] app.py đã có route /datasource, không chèn thêm.")
else:
    block = '''

@app.route("/datasource", methods=["GET"])
def datasource_page():
    from flask import render_template
    # Trang Data Source: chỉ hiển thị phần JSON / summary (Tool rules đang bị ẩn bằng active_page != 'tool_rules')
    return render_template("datasource.html")
'''

    # chèn TRƯỚC if __name__ == '__main__'
    m = re.search(r"if __name__ == ['\\\"]__main__['\\\"]:", text)
    if m:
        pos = m.start()
        text = text[:pos] + block + "\n" + text[pos:]
        print("[OK] Đã chèn route /datasource trước if __name__ == '__main__':")
    else:
        text = text.rstrip() + block + "\n"
        print("[WARN] Không thấy if __name__ == '__main__', append block ở cuối file.")

    app_path.write_text(text, encoding="utf-8")

PY

# check syntax
python3 -m py_compile "$APP" && echo "[OK] app.py compile ok"

echo "[DONE] patch_restore_datasource_route.sh hoàn thành."
