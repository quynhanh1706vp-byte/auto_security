#!/usr/bin/env bash
set -euo pipefail

APP="app.py"

echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP trong $(pwd)"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, textwrap

path = sys.argv[1]
data = open(path, encoding="utf-8").read()

if '@app.route("/scan_one"' in data:
    print("[INFO] Đã có route /scan_one trong app.py, không chèn nữa.")
    sys.exit(0)

route_block = textwrap.dedent("""
    @app.route("/scan_one", methods=["GET"])
    def scan_one():
        \"""Compat route cũ: trả về trạng thái scan (stub).\"""
        from flask import jsonify
        return jsonify({
            "ok": True,
            "status": "idle",
            "state": "idle",
            "running": False,
            "message": "UI chỉ xem kết quả run sẵn. Chạy scan bằng CLI rồi refresh Dashboard."
        })
""")

new = data.rstrip() + "\\n\\n" + route_block + "\\n"

with open(path, "w", encoding="utf-8") as f:
    f.write(new)

print("[OK] Đã chèn route /scan_one vào", path)
PY

echo "[DONE] sb_add_scan_one_stub.sh hoàn thành."
