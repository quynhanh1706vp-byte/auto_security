#!/usr/bin/env bash
set -euo pipefail

UI="/home/test/Data/SECURITY_BUNDLE/ui"
APP="$UI/app.py"

echo "[i] UI = $UI"

########################################
# 1) Thêm nav-item "Tool Rules" vào menu
########################################
python3 - <<'PY'
from pathlib import Path

ui = Path("/home/test/Data/SECURITY_BUNDLE/ui")
templates = [
    "templates/base.html",
    "templates/index.html",
    "templates/runs.html",
    "templates/datasource.html",
    "templates/settings.html",
]

snippet = '<div class="nav-item"><a href="/datasource">Data Source</a></div>'
insert = snippet + '\n          <div class="nav-item"><a href="/tool_rules">Tool Rules</a></div>'

for rel in templates:
    p = ui / rel
    if not p.exists():
        continue
    txt = p.read_text(encoding="utf-8")
    orig = txt
    if '/tool_rules' in txt:
        print(f"[INFO] {rel} đã có Tool Rules, bỏ qua.")
        continue

    if snippet in txt:
        txt = txt.replace(snippet, insert, 1)
        p.write_text(txt, encoding="utf-8")
        print(f"[OK] Đã chèn Tool Rules sau Data Source trong {rel}")
    else:
        # fallback: chỉ thêm link đơn giản nếu có chữ Data Source
        if 'href="/datasource"' in txt:
            txt = txt.replace('href="/datasource">Data Source</a>',
                              'href="/datasource">Data Source</a></div>\n          <div class="nav-item"><a href="/tool_rules">Tool Rules</a>',
                              1)
            p.write_text(txt, encoding="utf-8")
            print(f"[OK] Đã chèn Tool Rules (fallback) trong {rel}")
        else:
            print(f"[WARN] Không tìm thấy nav Data Source trong {rel}, không sửa.")
PY

########################################
# 2) Thêm route /tool_rules -> redirect sang /datasource
########################################
python3 - <<'PY'
from pathlib import Path
import re

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/app.py")
text = app_path.read_text(encoding="utf-8")
orig = text

if '@app.route("/tool_rules"' in text:
    print("[INFO] app.py đã có route /tool_rules, không chèn thêm.")
else:
    block = r"""

@app.route("/tool_rules", methods=["GET"])
def tool_rules_redirect():
    from flask import redirect, url_for
    return redirect(url_for("datasource"))
"""

    # chèn TRƯỚC if __name__ == '__main__':
    m = re.search(r"if __name__ == ['\\\"]__main__['\\\"]:", text)
    if m:
        pos = m.start()
        text = text[:pos] + block + "\n" + text[pos:]
        print("[OK] Đã chèn route /tool_rules trước if __name__ == '__main__':")
    else:
        text = text.rstrip() + block + "\n"
        print("[WARN] Không thấy if __name__ == '__main__':, append block ở cuối file.")

    app_path.write_text(text, encoding="utf-8")

PY

# 3) Kiểm tra syntax
python3 -m py_compile "$APP" && echo "[OK] app.py compile ok"

echo "[DONE] patch_tool_rules_tab.sh hoàn thành."
