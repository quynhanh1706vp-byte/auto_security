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

cp "$APP" "${APP}.bak_add_tool_rules_v2_v2_fallback_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup app.py."

python3 - << 'PY'
from pathlib import Path

path = Path("app.py")
data = path.read_text(encoding="utf-8")

marker = "### SB_TOOL_RULES_FALLBACK_V2_V2"
if marker in data:
    print("[INFO] Đã có block SB_TOOL_RULES_FALLBACK_V2_V2, bỏ qua.")
else:
    # Chèn block ngay trước SB_FORCE_MAIN_RUN_UI_V1 (trước app.run)
    insert_at = data.find("### SB_FORCE_MAIN_RUN_UI_V1")
    if insert_at == -1:
        insert_at = len(data)

    block = '''

### SB_TOOL_RULES_FALLBACK_V2_V2
# Alias API cho UI: /api/tool_rules_v2_v2
@app.route("/api/tool_rules_v2_v2", methods=["GET"])
def api_tool_rules_v2_v2_sb():
    """
    Trả về danh sách tool rules cho tab Settings/Data Source.
    Đọc trực tiếp static/last_tool_config.json.
    """
    import os, json
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

    # Nếu file là list thì bọc vào field tools, cho UI dễ dùng
    if isinstance(cfg, list):
        payload = {"status": "ok", "tools": cfg}
    else:
        payload = {"status": "ok", "data": cfg}

    return jsonify(payload)
'''
    new_data = data[:insert_at] + block + data[insert_at:]
    path.write_text(new_data, encoding="utf-8")
    print("[OK] Đã chèn route /api/tool_rules_v2_v2 vào app.py.")
PY

echo "[DONE] patch_add_tool_rules_v2_v2_fallback.sh hoàn thành."
