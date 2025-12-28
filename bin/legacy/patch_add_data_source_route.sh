#!/usr/bin/env bash
set -euo pipefail

APP="app.py"

echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP trong thư mục hiện tại."
  exit 1
fi

python3 - "$APP" <<'PY'
from pathlib import Path
import re

path = Path("app.py")
data = path.read_text(encoding="utf-8")

if "/data_source" in data:
    print("[INFO] Route /data_source đã tồn tại, không sửa.")
    raise SystemExit(0)

block = """

@app.route('/data_source')
def data_source():
    # Trang cấu hình nguồn dữ liệu JSON / output scan
    return render_template('data_source.html')
"""

# cố gắng chèn sau route /settings nếu tìm được
pattern = r"(@app.route\('/settings'[^\\n]*\\)\\s+def\\s+settings\\([^)]*\\):[\\s\\S]+?return[^\n]+)"
m = re.search(pattern, data)

if m:
    new_data = data[:m.end()] + block + data[m.end():]
    print("[OK] Đã chèn route /data_source sau /settings.")
else:
    new_data = data + block
    print("[WARN] Không tìm thấy route /settings, append route /data_source ở cuối file.")

path.write_text(new_data, encoding="utf-8")
PY

echo "[DONE] patch_add_data_source_route.sh hoàn thành."
