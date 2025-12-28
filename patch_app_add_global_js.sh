#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/app.py"

echo "[i] ROOT = $ROOT"
echo "[i] APP  = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy app.py"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys

path = sys.argv[1]
print("[PY] Đọc", path)
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

marker = '/static/patch_global_ui.js'
if marker in src:
    print("[PY] Đã có /static/patch_global_ui.js trong app.py, bỏ qua.")
    raise SystemExit(0)

needle = "</body>"
if needle not in src:
    print("[PY][ERR] Không tìm thấy </body> trong app.py – không chèn được script.")
    raise SystemExit(1)

snippet = '<script src="/static/patch_global_ui.js"></script>\\n</body>'

# chèn vào TẤT CẢ các </body> (các block HTML đều có JS này)
src = src.replace(needle, snippet)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

print("[PY] Đã chèn script /static/patch_global_ui.js trước </body> trong app.py")
PY

echo "[DONE] patch_app_add_global_js.sh hoàn thành."
