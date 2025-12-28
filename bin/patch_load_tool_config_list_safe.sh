#!/usr/bin/env bash
set -euo pipefail

APP="app.py"

echo "[i] Patch load_tool_config trong $APP để xử lý raw là list."

python3 - "$APP" <<'PY'
from pathlib import Path
import textwrap

path = Path("app.py")
data = path.read_text(encoding="utf-8")

needle = "    raw = json.load(f)\n"
if needle not in data:
    print("[WARN] Không tìm thấy 'raw = json.load(f)' trong app.py – không patch được.")
else:
    replace = """    raw = json.load(f)
    # Chuẩn hoá raw: có thể là dict (chuẩn) hoặc list (do file tool_config.json bị sửa)
    from collections.abc import Mapping
    if isinstance(raw, list):
        converted = {}
        for item in raw:
            if isinstance(item, dict):
                key = item.get("id") or item.get("tool_id") or item.get("name")
                if key:
                    converted[key] = item
        raw = converted
    elif not isinstance(raw, Mapping):
        # Nếu không phải dict/list thì fallback rỗng
        raw = {}
"""

    new_data = data.replace(needle, replace)
    if new_data == data:
        print("[WARN] Thay thế không thành công (không đổi nội dung).")
    else:
        path.write_text(new_data, encoding="utf-8")
        print("[OK] Đã patch load_tool_config – raw list giờ không làm vỡ UI nữa.")
PY

echo "[DONE] patch_load_tool_config_list_safe.sh hoàn thành."
