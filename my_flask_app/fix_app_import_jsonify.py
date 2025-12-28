from pathlib import Path
import re

p = Path("app.py")
text = p.read_text(encoding="utf-8")

m = re.search(r"from flask import ([^\n]+)", text)
if not m:
    print("[WARN] Không tìm thấy dòng 'from flask import ...' trong app.py")
else:
    imports = m.group(1)
    if "jsonify" in imports:
        print("[OK] app.py đã import jsonify, không cần sửa.")
    else:
        new_imports = imports.strip()
        # tránh dấu phẩy dư
        if new_imports.endswith(","):
            new_imports = new_imports[:-1].rstrip()
        new_line = "from flask import " + new_imports + ", jsonify\n"
        old_line = m.group(0) + "\n"
        text = text.replace(old_line, new_line)
        p.write_text(text, encoding="utf-8")
        print("[FIX] Đã thêm jsonify vào import flask:")
        print("      ", new_line.strip())
