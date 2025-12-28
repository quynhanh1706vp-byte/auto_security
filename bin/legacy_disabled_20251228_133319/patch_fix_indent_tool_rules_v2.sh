#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
APP="$ROOT/app.py"

echo "[i] ROOT = $ROOT"
cd "$ROOT"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP" >&2
  exit 1
fi

cp "$APP" "${APP}.bak_fix_indent_tool_rules_v2_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup app.py."

python3 - << 'PY'
import re
from pathlib import Path

path = Path("app.py")
data = path.read_text(encoding="utf-8")

# Tìm đoạn: if ...: (có thể có line trống) rồi tới @app.route("/api/tool_rules_v2", ...)
pattern = r'(if[^\n]*:\n)(\s*\n)*(@app\\.route\\("/api/tool_rules_v2", methods=\\["GET"\\]\\))'

def repl(m):
    head = m.group(1)
    route = m.group(3)
    return head + "    pass  # auto-fix: thêm block rỗng trước tool_rules_v2\n\n" + route

new_data, n = re.subn(pattern, repl, data, count=1, flags=re.MULTILINE)
if n == 0:
    print("[WARN] Không tìm thấy pattern if... + @app.route('/api/tool_rules_v2'), không sửa được.")
else:
    path.write_text(new_data, encoding="utf-8")
    print(f"[OK] Đã chèn 'pass' sau if trước tool_rules_v2 (match={n}).")
PY

echo "[DONE] patch_fix_indent_tool_rules_v2.sh hoàn thành."
