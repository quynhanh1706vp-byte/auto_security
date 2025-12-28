#!/usr/bin/env bash
set -euo pipefail

APP="app.py"

echo "[i] Sửa ký tự '\\n' thừa trước def save_tool_config_from_form trong $APP."

python3 - "$APP" <<'PY'
from pathlib import Path

path = Path("app.py")
data = path.read_text(encoding="utf-8")

old = "\\ndef save_tool_config_from_form("
new = "\ndef save_tool_config_from_form("

if old not in data:
    print("[WARN] Không tìm thấy chuỗi '\\\\ndef save_tool_config_from_form(' để sửa.")
else:
    data = data.replace(old, new)
    path.write_text(data, encoding="utf-8")
    print("[OK] Đã thay '\\\\ndef save_tool_config_from_form(' -> '\\ndef save_tool_config_from_form('")
PY

echo "[DONE] patch_app_fix_backslash.sh hoàn thành."
