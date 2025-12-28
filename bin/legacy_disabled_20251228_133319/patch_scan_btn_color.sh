#!/usr/bin/env bash
set -euo pipefail

TPL="templates/index.html"
echo "[i] TPL = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
html = path.read_text(encoding="utf-8")

pattern = r"(\\.scan-btn\\s*\\{[^}]*background:)[^;]*;"
replacement = r"\\1 linear-gradient(90deg,#6366f1,#ec4899);"

new_html, n = re.subn(pattern, replacement, html, count=1, flags=re.DOTALL)
if n == 0:
    print("[WARN] Không tìm thấy .scan-btn background để patch.")
else:
    path.write_text(new_html, encoding="utf-8")
    print(f"[OK] Đã đổi màu nút .scan-btn sang xanh basic (Dashboard ~ Run).")
PY
