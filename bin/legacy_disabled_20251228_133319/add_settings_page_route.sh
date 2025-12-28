#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
code = path.read_text(encoding="utf-8")

if "def settings_page(" in code:
    print("[INFO] Đã có settings_page(), bỏ qua.")
    sys.exit(0)

append = """

@app.route("/settings", methods=["GET"])
def settings_page():
    \"""
    Trang Settings – xem Tool config (dùng dữ liệu từ /api/dashboard_data).
    Hiện tại read-only; chỉnh sửa vẫn làm bằng file tool_config.json.
    \"""
    return render_template("settings.html")
"""

code = code.rstrip() + append + "\\n"
path.write_text(code, encoding="utf-8")
print("[OK] Đã thêm route /settings -> settings.html.")
PY
