#!/usr/bin/env bash
set -e

APP="app.py"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không thấy $APP trong thư mục hiện tại."
  exit 1
fi

# Backup an toàn
cp "$APP" "${APP}.bak_ui5_force_$(date +%Y%m%d_%H%M%S)"

python3 - "$APP" << 'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

# Nếu đã có route /ui5 thì thôi
if "def ui5_full(" in data or '@app.route("/ui5"' in data:
    print("[i] Route /ui5 đã tồn tại, không patch nữa.")
    sys.exit(0)

# Tìm vị trí block if __name__ == "__main__"
marker_pos = data.rfind("if __name__")
if marker_pos == -1:
    # fallback: chèn trước từ "app.run" nếu có
    marker_pos = data.rfind("app.run")
    if marker_pos == -1:
        marker_pos = len(data)

route_block = '''

# ==== UI5 FULL STATIC 5-PAGES (SECURITY_BUNDLE_FULL_5_PAGES.html) ====
from pathlib import Path as _Path_ui5

@app.route("/ui5", methods=["GET"])
def ui5_full():
    """Serve static 5-tabs SECURITY_BUNDLE_FULL_5_PAGES.html."""
    base = _Path_ui5(__file__).resolve().parent
    html_path = base / "my_flask_app" / "my_flask_app" / "SECURITY_BUNDLE_FULL_5_PAGES.html"
    try:
        return html_path.read_text(encoding="utf-8")
    except Exception as e:
        return f"<h1>UI5 error</h1><pre>{e}</pre>", 500

'''

new_data = data[:marker_pos] + route_block + data[marker_pos:]
path.write_text(new_data, encoding="utf-8")
print("[OK] Đã chèn route /ui5 trước block main trong app.py")
PY
