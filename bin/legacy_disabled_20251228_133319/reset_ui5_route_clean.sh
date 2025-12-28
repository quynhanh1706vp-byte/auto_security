#!/usr/bin/env bash
set -e

APP="app.py"
cp "$APP" "${APP}.bak_ui5reset_$(date +%Y%m%d_%H%M%S)"

python3 - "$APP" << 'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
lines = text.splitlines()

new_lines = []
i = 0

while i < len(lines):
    line = lines[i]
    # Tìm và xoá toàn bộ block route /ui5 cũ (decorator + def + thân hàm)
    if '@app.route("/ui5")' in line.replace("'", '"'):
        i += 1
        # bỏ dòng def
        if i < len(lines) and lines[i].lstrip().startswith("def "):
            i += 1
            # bỏ thân hàm (các dòng thụt đầu dòng)
            while i < len(lines):
                if lines[i].strip() == "":
                    # giữ lại 1 dòng trống rồi thoát
                    new_lines.append(lines[i])
                    i += 1
                    break
                if not lines[i].startswith((" ", "\t")):
                    # ra khỏi block hàm
                    break
                i += 1
        continue
    else:
        new_lines.append(line)
        i += 1

text = "\n".join(new_lines)

marker = 'if __name__ == "__main__":'
idx = text.rfind(marker)
if idx == -1:
    idx = len(text)

route_block = '''

# ==== STATIC 5-TABS UI (/ui5) ====
from pathlib import Path as _PathUi5

@app.route("/ui5", methods=["GET"])
def ui5_full_pages():
    """Serve static SECURITY_BUNDLE_FULL_5_PAGES.html (5 tabs demo)."""
    base = _PathUi5(__file__).resolve().parent
    html_path = base / "my_flask_app" / "my_flask_app" / "SECURITY_BUNDLE_FULL_5_PAGES.html"
    try:
        return html_path.read_text(encoding="utf-8")
    except Exception as exc:
        return f"<h1>UI5 error</h1><pre>{exc}</pre>", 500

'''

text = text[:idx] + route_block + "\n" + text[idx:]
path.write_text(text, encoding="utf-8")
print("[OK] Đã reset route /ui5 trong app.py")
PY
