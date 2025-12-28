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

cp "$APP" "${APP}.bak_fix_indent_line1490_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup app.py."

python3 - << 'PY'
from pathlib import Path

path = Path("app.py")
lines = path.read_text(encoding="utf-8").splitlines(keepends=True)

target_lineno = 1490  # theo báo lỗi
idx = target_lineno - 1  # index 0-based

if idx >= len(lines):
    print(f"[ERR] File chỉ có {len(lines)} dòng, không chạm được line 1490.")
else:
    line = lines[idx]
    print(f"[INFO] line 1490 hiện tại: {line!r}")

    stripped = line.strip()
    if stripped.startswith("if ") and stripped.endswith(":"):
        # Kiểm tra xem dòng sau đã có 'pass' chưa
        insert_line = "    pass  # auto-fix: thêm block rỗng sau if (tool_rules_v2)\n"
        already_ok = False
        if idx + 1 < len(lines):
            next_stripped = lines[idx + 1].strip()
            if next_stripped.startswith("pass"):
                already_ok = True

        if already_ok:
            print("[INFO] Dòng sau if đã có pass, không chèn thêm.")
        else:
            lines.insert(idx + 1, insert_line)
            path.write_text("".join(lines), encoding="utf-8")
            print("[OK] Đã chèn 'pass' vào sau line 1490.")
    else:
        print("[WARN] line 1490 không phải 'if ...:', không sửa gì để tránh hỏng file.")
PY

echo "[DONE] patch_fix_indent_line1490.sh hoàn thành."
