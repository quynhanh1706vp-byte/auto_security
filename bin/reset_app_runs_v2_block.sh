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

start = end = None
for i, line in enumerate(lines):
    if "# === AUTO PATCH: alias /api/runs_v2 ===" in line:
        start = i
    if "# === END AUTO PATCH ===" in line and start is not None:
        end = i
        break

if start is None or end is None:
    print("[WARN] Không tìm thấy block alias /api/runs_v2 để reset.")
else:
    print(f"[INFO] Xoá block cũ từ dòng {start+1} tới {end+1}.")
    # giữ các dòng trước start và sau end
    new_lines = lines[:start] + lines[end+1:]

    # block mới, sạch sẽ, không có backslash
    patch_block = [
        "",
        "# === AUTO PATCH: alias /api/runs_v2 ===",
        "try:",
        "    api_runs  # type: ignore[name-defined]",
        "except NameError:",
        "    pass",
        "else:",
        "    @app.route(\"/api/runs_v2\", methods=[\"GET\"])",
        "    def api_runs_v2():  # type: ignore[func-returns-value]",
        "        \"\"\"Alias đơn giản, dùng chung logic với /api/runs.\"\"\"",
        "        return api_runs()",
        "# === END AUTO PATCH ===",
        "",
    ]

    new_lines.extend(patch_block)
    path.write_text(\"\\n\".join(new_lines) + \"\\n\", encoding=\"utf-8\")
    print(\"[OK] Đã ghi lại block alias /api/runs_v2 sạch sẽ.\")
PY

echo "[DONE] reset_app_runs_v2_block.sh hoàn thành."
