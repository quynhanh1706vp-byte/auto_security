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
import sys

path = Path("app.py")
data = path.read_text(encoding="utf-8")

start = data.find("# === AUTO PATCH: alias /api/runs_v2 ===")
if start == -1:
    print("[WARN] Không tìm thấy block alias /api/runs_v2.")
    sys.exit(0)

end = data.find("# === END AUTO PATCH ===", start)
if end == -1:
    print("[WARN] Không tìm thấy '# === END AUTO PATCH ===' sau block alias, bỏ qua.")
    sys.exit(0)

# tìm hết dòng chứa END
end_newline = data.find("\n", end)
if end_newline == -1:
    end_pos = len(data)
else:
    end_pos = end_newline + 1

new_data = data[:start] + data[end_pos:]
path.write_text(new_data, encoding="utf-8")
print("[OK] Đã xoá block alias /api/runs_v2 khỏi app.py")
PY

echo "[DONE] remove_runs_v2_block.sh hoàn thành."
