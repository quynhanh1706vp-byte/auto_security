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

lines = html.splitlines()
new_lines = []
patched = 0

for ln in lines:
    lstrip = ln.lstrip().lower()
    # tìm đúng dòng button Run scan trên Dashboard
    if ("run scan" in lstrip) and ("button" in lstrip):
        if 'id="scan-btn"' not in ln and "id='scan-btn'" not in ln:
            ln = ln.replace("<button ", "<button id=\"scan-btn\" ", 1)
            patched += 1
    new_lines.append(ln)

path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
print(f"[OK] Đã patch {patched} dòng button Run scan (thêm id=scan-btn).")
PY
