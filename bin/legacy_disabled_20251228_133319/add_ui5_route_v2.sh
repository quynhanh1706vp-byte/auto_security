#!/usr/bin/env bash
set -e

APP="app.py"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không thấy $APP trong thư mục hiện tại."
  exit 1
fi

# Backup trước
cp "$APP" "${APP}.bak_ui5_$(date +%Y%m%d_%H%M%S)"

python3 - "$APP" << 'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

if '/ui5' in data:
    print("[i] Route /ui5 đã tồn tại, không patch.")
    sys.exit(0)

marker = 'if __name__ == "__main__":'
idx = data.rfind(marker)
if idx == -1:
    raise SystemExit("[ERR] Không tìm thấy block if __name__ == '__main__' trong app.py")

route_block = '''

@app.route("/ui5", methods=["GET"])
def ui5_full():
    """Serve static 5-tabs SECURITY_BUNDLE_FULL_5_PAGES.html."""
    try:
        from pathlib import Path
        base = Path(__file__).resolve().parent
        html_path = base / "my_flask_app" / "my_flask_app" / "SECURITY_BUNDLE_FULL_5_PAGES.html"
        return html_path.read_text(encoding="utf-8")
    except Exception as e:
        return "<h1>UI5 error</h1><pre>{}</pre>".format(e), 500

'''

new_data = data[:idx] + route_block + "\n" + data[idx:]
path.write_text(new_data, encoding="utf-8")
print("[OK] Đã chèn route /ui5 vào app.py")
PY
