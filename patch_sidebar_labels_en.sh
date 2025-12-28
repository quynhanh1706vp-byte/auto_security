#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TPL="$ROOT/templates/index.html"

echo "[i] ROOT = $ROOT"
echo "[i] TPL  = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy templates/index.html"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys

path = sys.argv[1]
print("[PY] Đọc", path)

with open(path, "r", encoding="utf-8") as f:
    html = f.read()

replacements = {
    "Lần quét & Báo cáo": "Run & Report",
    "Cấu hình tool (JSON)": "Settings",
    "Nguồn dữ liệu": "Data Source",
}

changed = False
for old, new in replacements.items():
    if old in html:
        html = html.replace(old, new)
        print(f"[PY] Thay '{old}' -> '{new}'")
        changed = True
    else:
        print(f"[PY] Không tìm thấy '{old}' (bỏ qua).")

if not changed:
    print("[PY] Không có thay đổi nào.")
else:
    with open(path, "w", encoding="utf-8") as f:
        f.write(html)
    print("[PY] Đã ghi lại", path)
PY

echo "[DONE] patch_sidebar_labels_en.sh hoàn thành."
