#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[VSP_APP_MAIN]"
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
BACKUP="$APP.bak_ensure_main_$TS"
cp "$APP" "$BACKUP"
echo "$LOG_PREFIX [BACKUP] $APP -> $BACKUP"

# 1) Đảm bảo có import os
if ! grep -qE '(^|\s)import os(\s|$)' "$APP"; then
  echo "$LOG_PREFIX [INFO] Không thấy 'import os' – sẽ chèn thêm bên trên."
  # Chèn sau dòng đầu tiên "import" hoặc "from"
  if grep -qE '^(import|from) ' "$APP"; then
    python - "$APP" << 'PY'
import io,sys,re,pathlib
p = pathlib.Path(sys.argv[1])
txt = p.read_text(encoding="utf-8").splitlines()
out = []
inserted = False
for i,line in enumerate(txt):
    if not inserted and re.match(r'^(import|from)\s+', line):
        out.append("import os")
        inserted = True
    out.append(line)
p.write_text("\n".join(out), encoding="utf-8")
PY
  else
    # Không có import nào -> prepend
    python - "$APP" << 'PY'
import pathlib,sys
p = pathlib.Path(sys.argv[1])
txt = p.read_text(encoding="utf-8")
p.write_text("import os\n" + txt, encoding="utf-8")
PY
  fi
fi

# 2) Nếu đã có if __name__ == '__main__' thì không làm gì thêm
if grep -q "if __name__ == '__main__':" "$APP"; then
  echo "$LOG_PREFIX [OK] Đã có block main, không chèn thêm."
  exit 0
fi

echo "$LOG_PREFIX [INFO] Không thấy block main, sẽ append ở cuối file."

cat << 'PYAPPEND' >> "$APP"

if __name__ == '__main__':
    # VSP UI Gateway – default port 8910, có thể override bằng biến môi trường VSP_UI_PORT
    port = int(os.environ.get('VSP_UI_PORT', '8910'))
    # debug=False cho gần với bản thương mại; muốn xem log chi tiết thì đổi thành True
    app.run(host='0.0.0.0', port=port, debug=False)
PYAPPEND

echo "$LOG_PREFIX [DONE] Đã chèn block main chạy app.run(...) vào cuối $APP"
