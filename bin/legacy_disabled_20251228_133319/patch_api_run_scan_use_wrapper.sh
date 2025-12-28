#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"
APP="app.py"
echo "[i] APP = $APP"

python3 - <<'PY'
from pathlib import Path

path = Path("app.py")
text = path.read_text(encoding="utf-8")
old = text

if "run_all_tools_v2.sh" not in text:
    print("[WARN] Không thấy 'run_all_tools_v2.sh' trong app.py – có thể đã được sửa trước đó.")
else:
    text = text.replace("run_all_tools_v2.sh", "run_scan_and_refresh_ui.sh")
    path.write_text(text, encoding="utf-8")
    print("[OK] Đã thay run_all_tools_v2.sh -> run_scan_and_refresh_ui.sh trong app.py")
PY

echo "[DONE] patch_api_run_scan_use_wrapper.sh hoàn thành."
