#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

APP="app.py"

python3 - "$APP" << 'PY'
import sys, pathlib, textwrap

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

# Nếu route /v2 đã có thì thôi
if '@app.route("/v2")' in data:
    print("[i] Route /v2 đã tồn tại, bỏ qua.")
    sys.exit(0)

marker = "app = Flask(__name__"
idx = data.find(marker)
if idx == -1:
    raise SystemExit("Không tìm thấy 'app = Flask(__name__)' trong app.py")

# chèn ngay sau dòng app = Flask(...)
idx = data.find("\n", idx)
snippet = textwrap.dedent("""
@app.route("/v2")
def security_bundle_v2():
    \"\"\"Serve static SECURITY_BUNDLE_FULL_5_PAGES.html (5 tab)\"\"\"
    from flask import send_from_directory
    # Directory tính từ thư mục ui/
    return send_from_directory(
        "my_flask_app/my_flask_app",
        "SECURITY_BUNDLE_FULL_5_PAGES.html"
    )
""")

new_data = data[:idx+1] + snippet + data[idx+1:]
path.write_text(new_data, encoding="utf-8")
print("[OK] Đã thêm route /v2 để serve SECURITY_BUNDLE_FULL_5_PAGES.html")
PY
