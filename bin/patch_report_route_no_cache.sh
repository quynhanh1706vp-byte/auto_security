#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
code = path.read_text(encoding="utf-8")

# Đổi send_file(str(f)) -> send_file(str(f), conditional=False)
new_code, n = re.subn(
    r"return\s+send_file\(\s*str\(f\)\s*\)",
    "return send_file(str(f), conditional=False)",
    code,
    count=1,
)

if n == 0:
    print("[WARN] Không tìm thấy 'return send_file(str(f))' để patch.")
else:
    path.write_text(new_code, encoding="utf-8")
    print("[OK] Đã patch report_html: tắt conditional caching (luôn 200).")
PY
