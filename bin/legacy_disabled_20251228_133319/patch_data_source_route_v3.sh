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

path = Path("app.py")
data = path.read_text(encoding="utf-8")

# Nếu đã có hàm data_source thì thôi
if "def data_source(" in data:
    print("[INFO] Hàm data_source() đã tồn tại, không sửa.")
else:
    block = """

@app.route('/datasource')
@app.route('/data_source')
def data_source():
    # Trang cấu hình nguồn dữ liệu JSON / output scan
    return render_template('data_source.html')
"""
    data = data + block
    path.write_text(data, encoding="utf-8")
    print("[OK] Đã append route /datasource + /data_source vào cuối app.py")
PY

echo "[DONE] patch_data_source_route_v3.sh hoàn thành."
