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

path = Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

# Nếu đã có /api/runs_v2 rồi thì khỏi patch
if "/api/runs_v2" in data:
    print("[INFO] app.py đã có /api/runs_v2, bỏ qua.")
    sys.exit(0)

block = r"""

# === AUTO PATCH: alias /api/runs_v2 ===
try:
    # api_runs đã được định nghĩa ở trên trong app.py
    api_runs  # type: ignore[name-defined]
except NameError:
    pass
else:
    @app.route("/api/runs_v2", methods=["GET"])
    def api_runs_v2():  # type: ignore[func-returns-value]
        \"\"\"Alias đơn giản, dùng chung logic với /api/runs.\"\"\"
        return api_runs()
# === END AUTO PATCH ===

"""

data = data.rstrip() + block
path.write_text(data, encoding="utf-8")
print("[OK] Đã append alias /api/runs_v2 vào", path)
PY

echo "[DONE] add_runs_v2_alias_app.sh hoàn thành."
