#!/usr/bin/env bash
set -euo pipefail

CSS="static/css/security_resilient.css"
echo "[i] CSS = $CSS"

if [ ! -f "$CSS" ]; then
  echo "[ERR] Không tìm thấy $CSS"
  exit 1
fi

python3 - "$CSS" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
css = path.read_text(encoding="utf-8")

old = "height: calc(12px + min(var(--sev-count, 0) * 0.02px, 180px));"
new = "height: calc(6px + min(var(--sev-count, 0) * 1px, 190px));"

if old not in css:
    print("[WARN] Không tìm thấy dòng height cũ, có thể đã được sửa hoặc tên khác.")
else:
    css = css.replace(old, new)
    path.write_text(css, encoding="utf-8")
    print("[OK] Đã đổi scale chiều cao cột severity (x50 lần).")
PY
