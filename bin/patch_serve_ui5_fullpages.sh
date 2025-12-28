#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"
APP="app.py"

python3 - "$APP" << 'PY'
import sys, pathlib, textwrap

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

# Nếu đã có route /ui5 thì thôi
if '@app.route("/ui5")' in data:
    print("[i] Route /ui5 đã tồn tại, bỏ qua.")
    sys.exit(0)

# Đảm bảo có send_from_directory trong import
if "send_from_directory" not in data:
    if "from flask import Flask" in data:
        data = data.replace(
            "from flask import Flask",
            "from flask import Flask, send_from_directory"
        )
    else:
        data = "from flask import send_from_directory\n" + data

snippet = textwrap.dedent("""
@app.route("/ui5")
def ui5_full_pages():
    \"\"\"Serve static file SECURITY_BUNDLE_FULL_5_PAGES.html\"\"\"
    return send_from_directory(
        "my_flask_app/my_flask_app",
        "SECURITY_BUNDLE_FULL_5_PAGES.html"
    )
""")

path.write_text(data.rstrip() + "\\n\\n" + snippet + "\\n", encoding="utf-8")
print("[OK] Đã thêm route /ui5 -> SECURITY_BUNDLE_FULL_5_PAGES.html")
PY
