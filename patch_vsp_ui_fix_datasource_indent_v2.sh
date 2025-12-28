#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"

echo "[PATCH] Fix datasource_v2 proxy block indent trong $APP"

python - << 'PY'
from pathlib import Path

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
txt = app_path.read_text(encoding="utf-8")

# Tìm main guard để không động vào phần chạy app
main_mark = 'if __name__ == "__main__":'
alt_mark  = "if __name__ == '__main__':"

idx_main = txt.find(main_mark)
if idx_main == -1:
    idx_main = txt.find(alt_mark)

if idx_main == -1:
    print("[ERR] Không tìm thấy if __name__ == '__main__' trong vsp_demo_app.py – không dám sửa.")
    raise SystemExit(1)

head = txt[:idx_main].rstrip()
tail = txt[idx_main:]

# Tìm block datasource cũ (marker hoặc dòng import bị lỗi)
marker = "# === VSP_UI_DATASOURCE_FORCE_V3"
idx_block = head.find(marker)
if idx_block == -1:
    import_line = "from flask import request, Response"
    idx_block = head.find(import_line)

if idx_block == -1:
    print("[INFO] Không thấy block datasource cũ, sẽ chỉ chèn block mới trước main guard.")
    good_head = head
else:
    print("[OK] Cắt bỏ block datasource cũ từ index", idx_block)
    good_head = head[:idx_block].rstrip()

block = '''
# === VSP_UI_DATASOURCE_FORCE_V3 – proxy /api/vsp/datasource_v2 (UI 8910 -> core 8961) ===
from flask import request, Response  # safe nếu đã import trước
import requests, urllib.parse

@app.route("/api/vsp/datasource_v2", methods=["GET"])
def vsp_ui_datasource_v2():
    # Lấy toàn bộ query string & forward sang core
    qs = urllib.parse.urlencode(dict(request.args))
    core_url = "http://localhost:8961/api/vsp/datasource_v2"
    if qs:
        core_url = f"{core_url}?{qs}"

    try:
        r = requests.get(core_url, timeout=60)
        resp = Response(r.content, status=r.status_code)
        resp.headers["Content-Type"] = r.headers.get("Content-Type", "application/json")
        return resp
    except Exception as exc:
        return {"ok": False, "error": f"proxy datasource_v2 error: {exc}"}, 500
'''.strip()

new_txt = good_head + "\n\n" + block + "\n\n" + tail.lstrip()
app_path.write_text(new_txt, encoding="utf-8")
print("[OK] Đã ghi lại", app_path)
PY

echo "[PATCH] Done."
