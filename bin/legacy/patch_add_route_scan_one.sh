#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE"
APP=$(find "$ROOT" -maxdepth 2 -type f -name 'app.py' | head -n 1 || true)

if [ -z "$APP" ]; then
  echo "[ERR] Không tìm thấy app.py trong $ROOT"
  exit 1
fi

echo "[i] APP = $APP"

python3 - "$APP" <<'PY'
import sys, pathlib, textwrap

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

if "def scan_one(" in data:
    print("[INFO] app.py đã có route scan_one – bỏ qua.")
    sys.exit(0)

block = textwrap.dedent("""

@app.route('/scan_one')
def scan_one():
    \"""
    Trang 'RUN ONE PROJECT' – dùng chung context với Dashboard.
    \"""
    try:
        ctx = {}
        # nếu có hàm _sb_build_dashboard_data_ctx thì dùng luôn
        if '_sb_build_dashboard_data_ctx' in globals():
            ctx = _sb_build_dashboard_data_ctx()
        return render_template('scan_one.html', **ctx)
    except Exception as e:
        print('[SB][SCAN_ONE] Lỗi render scan_one:', e)
        return render_template('scan_one.html')
""")

data = data + block
path.write_text(data, encoding="utf-8")
print("[OK] Đã chèn route scan_one vào", path)
PY

echo "[DONE] patch_add_route_scan_one.sh hoàn thành."
