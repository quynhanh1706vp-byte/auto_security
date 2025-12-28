#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
from pathlib import Path

path = Path("app.py")
data = path.read_text(encoding="utf-8")
lines = data.splitlines()

changed = 0
for i, line in enumerate(lines):
    if "Alias đơn giản, dùng chung logic với /api/runs." in line:
        # Sửa nguyên cả dòng này thành docstring 3 nháy chuẩn
        lines[i] = '        """Alias đơn giản, dùng chung logic với /api/runs."""'
        changed += 1

if not changed:
    print("[WARN] Không tìm thấy dòng docstring alias để sửa.")
else:
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"[OK] Đã sửa {changed} dòng docstring alias /api/runs_v2.")
PY

echo "[DONE] fix_app_runs_v2_alias_quotes.sh hoàn thành."
