#!/usr/bin/env bash
set -euo pipefail

APP="app.py"

echo "[i] Override hàm load_tool_config trong $APP cho an toàn (dict + list)."

python3 - "$APP" <<'PY'
from pathlib import Path
import textwrap

path = Path("app.py")
data = path.read_text(encoding="utf-8")

needle = "def load_tool_config("
idx = data.find(needle)
if idx == -1:
    print("[ERR] Không tìm thấy 'def load_tool_config(' trong app.py – không patch được.")
else:
    # Tìm bắt đầu của hàm tiếp theo sau load_tool_config để cắt đúng block
    next_def = data.find("\ndef ", idx + 1)
    if next_def == -1:
        next_def = len(data)

    new_func = textwrap.dedent('''\
def load_tool_config():
    """Đọc tool_config.json, chấp nhận cả dict lẫn list, luôn trả về dict."""
    cfg_path = ROOT / "tool_config.json"
    if not cfg_path.exists():
        print("[WARN] Không tìm thấy", cfg_path)
        return {}

    import json
    try:
        raw = json.loads(cfg_path.read_text(encoding="utf-8"))
    except Exception as e:
        print("[WARN] Lỗi đọc tool_config.json:", e)
        return {}

    from collections.abc import Mapping

    # Trường hợp chuẩn: file là dict
    if isinstance(raw, Mapping):
        return raw

    # Trường hợp file là list các config
    if isinstance(raw, list):
        converted = {}
        for item in raw:
            if not isinstance(item, dict):
                continue
            tid = item.get("id") or item.get("tool_id") or item.get("name")
            if tid:
                converted[tid] = item
        return converted

    # Trường hợp kiểu khác: bỏ qua
    print("[WARN] tool_config.json không phải dict/list – trả về {}.")
    return {}
''')

    new_data = data[:idx] + new_func + "\n" + data[next_def+1:]
    path.write_text(new_data, encoding="utf-8")
    print("[OK] Đã override load_tool_config trong app.py")
PY

echo "[DONE] patch_load_tool_config_override_v2.sh hoàn thành."
