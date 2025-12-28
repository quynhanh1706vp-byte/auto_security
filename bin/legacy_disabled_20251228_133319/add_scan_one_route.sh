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

if "/scan_one" in data:
    print("[INFO] Đã có route /scan_one trong app.py, không chèn nữa.")
    sys.exit(0)

route_block = textwrap.dedent("""
    @app.route("/scan_one")
    def scan_one():
        \"""Compat route cũ: chuyển về trang chính Dashboard.\"""
        from flask import redirect, url_for
        return redirect(url_for("index"))
""")

new = data.rstrip() + "\n\n" + route_block + "\n"

open(path, "w", encoding="utf-8").write(new)
print("[OK] Đã chèn route /scan_one vào", path)
PY

echo "[DONE] add_scan_one_route.sh hoàn thành."
