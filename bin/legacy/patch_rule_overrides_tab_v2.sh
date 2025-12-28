#!/usr/bin/env bash
set -euo pipefail

UI="/home/test/Data/SECURITY_BUNDLE/ui"
APP="$UI/app.py"

echo "[i] UI = $UI"

########################################
# 1) Đảm bảo có route /tool_rules
########################################
python3 - <<'PY'
from pathlib import Path
import re

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/app.py")
text = app_path.read_text(encoding="utf-8")
orig = text

block = '''@app.route("/tool_rules", methods=["GET"])
def tool_rules_redirect():
    from flask import render_template
    # Trang Rule overrides riêng – dùng lại template datasource
    return render_template("datasource.html", active_page="tool_rules")
'''

if '@app.route("/tool_rules", methods=["GET"])' in text:
    # Chuẩn hoá nội dung body cho chắc
    text = re.sub(
        r'@app\.route\("/tool_rules", methods=\["GET"\]\)[\s\S]*?(?=\n@app\.route|\nif __name__ ==|$)',
        block + "\n",
        text,
        count=1,
    )
    print("[OK] Đã chuẩn hoá route /tool_rules.")
else:
    m = re.search(r"if __name__ == ['\\\"]__main__['\\\"]:", text)
    if m:
        pos = m.start()
        text = text[:pos] + "\n" + block + "\n" + text[pos:]
        print("[OK] Đã chèn route /tool_rules trước main block.")
    else:
        text = text.rstrip() + "\n" + block + "\n"
        print("[WARN] Không thấy main block, append /tool_rules ở cuối file.")

if text != orig:
    app_path.write_text(text, encoding="utf-8")
PY

########################################
# 2) Thêm tab "Rule overrides" ngay sau "Data Source"
#    Bắt TẤT CẢ dòng chứa href="/datasource" và chèn thêm 1 dòng mới phía dưới.
########################################
python3 - <<'PY'
from pathlib import Path

ui = Path("/home/test/Data/SECURITY_BUNDLE/ui")
for p in ui.glob("templates/*.html"):
    txt = p.read_text(encoding="utf-8")
    orig = txt

    # Nếu file đã có /tool_rules thì bỏ qua
    if '/tool_rules' in txt or 'Rule overrides' in txt:
        print(f"[INFO] {p.name}: đã có Rule overrides, bỏ qua.")
        continue

    lines = txt.splitlines()
    new_lines = []
    changed = False

    for line in lines:
        new_lines.append(line)
        if 'href="/datasource"' in line:
            # Lấy indent của dòng hiện tại
            indent = line[:len(line) - len(line.lstrip())]
            new_lines.append(
                f'{indent}<div class="nav-item"><a href="/tool_rules">Rule overrides</a></div>'
            )
            changed = True
            print(f"[OK] {p.name}: đã chèn Rule overrides sau Data Source.")

    if changed:
        p.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
    else:
        print(f"[INFO] {p.name}: không thấy href=\"/datasource\", không sửa.")
PY

########################################
# 3) Đổi title khi active_page = 'tool_rules'
########################################
python3 - <<'PY'
from pathlib import Path

tpl = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates/datasource.html")
if not tpl.exists():
    print("[WARN] Không thấy templates/datasource.html")
else:
    html = tpl.read_text(encoding="utf-8")
    orig = html
    marker = '<div class="sb-main-title">Data Source</div>'

    if "active_page == 'tool_rules'" in html:
        print("[INFO] datasource.html đã có logic title, bỏ qua.")
    elif marker in html:
        html = html.replace(
            marker,
            '<div class="sb-main-title">{% if active_page == \'tool_rules\' %}Rule overrides{% else %}Data Source{% endif %}</div>',
            1,
        )
        tpl.write_text(html, encoding="utf-8")
        print("[OK] Đã thêm title Rule overrides cho /tool_rules.")
    else:
        print("[WARN] Không tìm thấy sb-main-title Data Source để sửa.")
PY

echo "[DONE] patch_rule_overrides_tab_v2.sh hoàn thành."
