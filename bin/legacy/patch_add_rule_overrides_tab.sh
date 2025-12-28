#!/usr/bin/env bash
set -euo pipefail

UI="/home/test/Data/SECURITY_BUNDLE/ui"
APP="$UI/app.py"

echo "[i] UI = $UI"

########################################
# 1) Đảm bảo route /tool_rules đã render trang rule overrides
########################################
python3 - <<'PY'
from pathlib import Path
import re

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/app.py")
text = app_path.read_text(encoding="utf-8")
orig = text

new_block = '''@app.route("/tool_rules", methods=["GET"])
def tool_rules_redirect():
    from flask import render_template
    # Trang Rule overrides riêng – dùng lại template datasource
    return render_template("datasource.html", active_page="tool_rules")
'''

if '@app.route("/tool_rules", methods=["GET"])' in text:
    # Thay nội dung cũ (nếu khác) bằng block mới
    text = re.sub(
        r'@app\.route\("/tool_rules", methods=\["GET"\]\)[\s\S]*?(\n@app\.route|\nif __name__ ==|$)',
        new_block + r'\1',
        text,
        count=1,
    )
    print("[OK] Đã chuẩn hoá route /tool_rules.")
else:
    # Chưa có -> chèn trước if __name__ == '__main__'
    m = re.search(r"if __name__ == ['\\\"]__main__['\\\"]:", text)
    if m:
        pos = m.start()
        text = text[:pos] + "\n" + new_block + "\n" + text[pos:]
        print("[OK] Đã chèn route /tool_rules trước main block.")
    else:
        text = text.rstrip() + "\n" + new_block + "\n"
        print("[WARN] Không thấy main block, append /tool_rules ở cuối file.")

if text != orig:
    app_path.write_text(text, encoding="utf-8")
PY

########################################
# 2) Thêm tab "Rule overrides" sau "Data Source" trong menu
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
insert = snippet + '\n          <div class="nav-item"><a href="/tool_rules">Rule overrides</a></div>'

for rel in templates:
    p = ui / rel
    if not p.exists():
        continue
    txt = p.read_text(encoding="utf-8")
    orig = txt

    if 'Rule overrides' in txt or '/tool_rules' in txt:
        print(f"[INFO] {rel} đã có Rule overrides, bỏ qua.")
        continue

    if snippet in txt:
        txt = txt.replace(snippet, insert, 1)
        p.write_text(txt, encoding="utf-8")
        print(f"[OK] Đã thêm Rule overrides sau Data Source trong {rel}")
    elif 'href="/datasource"' in txt:
        txt = txt.replace(
            'href="/datasource">Data Source</a>',
            'href="/datasource">Data Source</a></div>\n          <div class="nav-item"><a href="/tool_rules">Rule overrides</a>',
            1,
        )
        p.write_text(txt, encoding="utf-8")
        print(f"[OK] (fallback) Đã thêm Rule overrides trong {rel}")
    else:
        print(f"[WARN] Không tìm thấy nav Data Source trong {rel}, không sửa.")
PY

########################################
# 3) Đổi title khi active_page = 'tool_rules'
########################################
python3 - <<'PY'
from pathlib import Path

tpl = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates/datasource.html")
html = tpl.read_text(encoding="utf-8")
orig = html

marker = '<div class="sb-main-title">Data Source</div>'

if "active_page == 'tool_rules'" in html:
    print("[INFO] datasource.html đã có logic title theo active_page.")
else:
    if marker in html:
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

echo "[DONE] patch_add_rule_overrides_tab.sh hoàn thành."
