#!/usr/bin/env bash
set -euo pipefail

UI="/home/test/Data/SECURITY_BUNDLE/ui"
APP="$UI/app.py"
TPL="$UI/templates/datasource.html"

echo "[i] UI = $UI"

########################################
# 1) Sửa route /tool_rules -> render_template("datasource.html", active_page="tool_rules")
########################################
python3 - <<'PY'
from pathlib import Path

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/app.py")
text = app_path.read_text(encoding="utf-8")
orig = text

old_block = '''@app.route("/tool_rules", methods=["GET"])
def tool_rules_redirect():
    from flask import redirect
    # redirect thẳng sang path /datasource (không dùng endpoint name)
    return redirect("/datasource")
'''

new_block = '''@app.route("/tool_rules", methods=["GET"])
def tool_rules_redirect():
    from flask import render_template
    # Trang Tool Rules riêng: dùng lại template datasource nhưng chỉ show block Tool rules
    return render_template("datasource.html", active_page="tool_rules")
'''

if old_block in text:
    text = text.replace(old_block, new_block)
    print("[OK] Đã thay body tool_rules_redirect() sang render_template(datasource.html, active_page='tool_rules').")
elif new_block in text:
    print("[INFO] app.py đã ở chế độ page Tool Rules, không đổi.")
elif '@app.route("/tool_rules", methods=["GET"])' in text:
    # Trường hợp nội dung khác → đơn giản append new_block (bạn hiếm gặp)
    text += "\n" + new_block + "\n"
    print("[WARN] Không match được block cũ, đã append block mới.")
else:
    # Chưa hề có route /tool_rules → thêm mới trước if __name__ == '__main__'
    import re
    block = "\n" + new_block + "\n"
    import re
    m = re.search(r"if __name__ == ['\\\"]__main__['\\\"]:", text)
    if m:
        pos = m.start()
        text = text[:pos] + block + text[pos:]
        print("[OK] Đã chèn route /tool_rules trước if __name__ == '__main__':")
    else:
        text = text.rstrip() + block + "\n"
        print("[WARN] Không thấy if __name__ == '__main__', append block ở cuối file.")

if text != orig:
    app_path.write_text(text, encoding="utf-8")
PY

########################################
# 2) datasource.html: nếu active_page == 'tool_rules' thì ẩn phần SAMPLE FINDINGS,
# chỉ show block Tool rules ở trên cùng
########################################
python3 - <<'PY'
from pathlib import Path

tpl_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates/datasource.html")
html = tpl_path.read_text(encoding="utf-8")
orig = html

# Nếu đã có guard active_page thì thôi
if "active_page == 'tool_rules'" in html:
    print("[INFO] datasource.html đã có guard active_page, không sửa.")
else:
    marker = "<!-- === Tool rules / Rule overrides"
    idx = html.find(marker)
    if idx == -1:
        print("[WARN] Không tìm thấy marker Tool rules trong datasource.html – không sửa được layout.")
    else:
        top = html[:idx]
        bottom = html[idx:]
        wrapped_top = (
            "{% if active_page != 'tool_rules' %}\n"
            + top +
            "{% endif %}\n"
        )
        html = wrapped_top + bottom
        tpl_path.write_text(html, encoding="utf-8")
        print("[OK] Đã bọc phần SAMPLE FINDINGS bằng active_page != 'tool_rules'.")
PY

# 3) Check syntax app.py
python3 -m py_compile "$APP" && echo "[OK] app.py compile ok"

echo "[DONE] patch_tool_rules_page_mode.sh hoàn thành."
