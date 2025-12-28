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

cp "$APP" "${APP}.bak_add_tool_rules_v2_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup app.py."

python3 - << 'PY'
from pathlib import Path
import json

path = Path("app.py")
data = path.read_text(encoding="utf-8")

# Nếu đã có route rồi thì thôi
if '@app.route("/api/tool_rules_v2"' in data:
    print("[INFO] Đã có /api/tool_rules_v2 trong app.py, bỏ qua.")
else:
    marker = "### SB_FORCE_MAIN_RUN_UI_V1"
    insert_at = data.find(marker)
    if insert_at == -1:
        # nếu chưa có marker thì chèn cuối file
        insert_at = len(data)

    block = '''

# ========== API: tool_rules_v2 – đọc từ static/last_tool_config.json ==========
@app.route("/api/tool_rules_v2", methods=["GET"])
def api_tool_rules_v2():
    """
    Trả về danh sách tool-rules cho UI (Settings / Data Source).
    Đọc trực tiếp file static/last_tool_config.json nếu có.
    """
    import os
    from flask import jsonify

    root = os.path.dirname(os.path.abspath(__file__))
    cfg_path = os.path.join(root, "static", "last_tool_config.json")

    if not os.path.exists(cfg_path):
        return jsonify({
            "status": "error",
            "error": "last_tool_config.json not found",
            "path": cfg_path,
        }), 404

    try:
        with open(cfg_path, "r", encoding="utf-8") as f:
            cfg = json.load(f)
    except Exception as e:
        return jsonify({
            "status": "error",
            "error": f"Cannot parse last_tool_config.json: {e}",
            "path": cfg_path,
        }), 500

    # Cho UI dễ dùng: bọc vào field tools nếu bản gốc là list
    if isinstance(cfg, list):
        payload = {"status": "ok", "tools": cfg}
    else:
        payload = {"status": "ok", "data": cfg}

    return jsonify(payload)
'''

    new_data = data[:insert_at] + block + data[insert_at:]
    path.write_text(new_data, encoding="utf-8")
    print("[OK] Đã chèn route /api/tool_rules_v2 vào app.py.")
PY

echo "[DONE] patch_add_tool_rules_v2_simple.sh hoàn thành."
