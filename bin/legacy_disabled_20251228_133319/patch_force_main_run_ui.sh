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

cp "$APP" "${APP}.bak_force_main_run_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup app.py."

python3 - << 'PY'
from pathlib import Path

path = Path("app.py")
data = path.read_text(encoding="utf-8")

marker = "### SB_FORCE_MAIN_RUN_UI_V1"
if marker in data:
    print("[INFO] Block SB_FORCE_MAIN_RUN_UI_V1 đã tồn tại, không append nữa.")
else:
    block = f"""

{marker}
if __name__ == "__main__":
    print("[INFO] SECURITY_BUNDLE UI starting on 0.0.0.0:8905 (SB_FORCE_MAIN_RUN_UI_V1)")
    # Debug = True để auto-reload khi sửa template/static
    app.run(host="0.0.0.0", port=8905, debug=True)
"""
    data = data.rstrip() + block + "\\n"
    path.write_text(data, encoding="utf-8")
    print("[OK] Đã append block SB_FORCE_MAIN_RUN_UI_V1 vào cuối app.py.")
PY

echo "[DONE] patch_force_main_run_ui.sh hoàn thành."
