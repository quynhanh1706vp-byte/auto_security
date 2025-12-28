#!/usr/bin/env bash
set -euo pipefail

TPL="templates/index.html"
echo "[i] TPL = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
html = path.read_text(encoding="utf-8")

target = (
    "Critical / High / Medium / Low – các bucket được tính như sau: "
    "Critical, High, Medium là severity gốc; Low bao gồm cả Info & Unknown "
    "(và các cảnh báo nhẹ). Dữ liệu lấy từ findings_unified.json của RUN mới nhất."
)

if target in html:
    html = html.replace(target, "")
    print("[OK] Đã xoá đoạn note dài khỏi Dashboard.")
else:
    print("[WARN] Không tìm thấy đúng chuỗi target trong templates/index.html")

path.write_text(html, encoding="utf-8")
PY
