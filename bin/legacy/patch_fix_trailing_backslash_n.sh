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

cp "$APP" "${APP}.bak_fix_trailing_bslash_n_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup app.py."

python3 - << 'PY'
from pathlib import Path

path = Path("app.py")
lines = path.read_text(encoding="utf-8").splitlines(keepends=True)

new_lines = []
removed = 0

for line in lines:
    # Nếu dòng chỉ có "\n" (có thể có space/tab trước) thì bỏ
    if line.strip() == r"\n":
        removed += 1
        continue
    new_lines.append(line)

path.write_text("".join(new_lines), encoding="utf-8")
print(f"[OK] Đã xoá {removed} dòng '\\n' thừa (nếu có).")
PY

echo "[DONE] patch_fix_trailing_backslash_n.sh hoàn thành."
