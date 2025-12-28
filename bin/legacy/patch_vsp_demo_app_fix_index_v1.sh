#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[VSP_FIX_INDEX]"
BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
APP="$UI_ROOT/vsp_demo_app.py"

echo "$LOG_PREFIX UI_ROOT = $UI_ROOT"
echo "$LOG_PREFIX APP    = $APP"

if [ ! -f "$APP" ]; then
  echo "$LOG_PREFIX [ERR] Không tìm thấy $APP"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="$APP.bak_fix_index_$TS"
cp "$APP" "$BACKUP"
echo "$LOG_PREFIX [BACKUP] $APP -> $BACKUP"

python - "$APP" << 'PY'
import pathlib, re, sys

p = pathlib.Path(sys.argv[1])
txt = p.read_text(encoding="utf-8")

pattern = r"render_template\(\s*['\"]index\.html['\"]\s*\)"
replacement = "render_template('vsp_dashboard_2025.html')"

new_txt, n = re.subn(pattern, replacement, txt)
print("[VSP_FIX_INDEX] replacements:", n)

if n == 0:
    print("[VSP_FIX_INDEX] WARNING: Không tìm thấy 'render_template(\"index.html\")' trong file, không sửa gì.")
else:
    p.write_text(new_txt, encoding="utf-8")
PY

echo "$LOG_PREFIX [DONE] Nếu có replacements > 0 thì route / giờ sẽ render vsp_dashboard_2025.html."
