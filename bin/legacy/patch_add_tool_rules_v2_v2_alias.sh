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

cp "$APP" "${APP}.bak_add_tool_rules_v2_v2_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup app.py."

python3 - << 'PY'
from pathlib import Path

path = Path("app.py")
data = path.read_text(encoding="utf-8")

if '@app.route("/api/tool_rules_v2_v2"' in data:
    print("[INFO] Đã có /api/tool_rules_v2_v2, bỏ qua.")
else:
    # Chèn alias ngay sau định nghĩa api_tool_rules_v2 nếu có
    marker = "def api_tool_rules_v2():"
    idx = data.find(marker)
    if idx == -1:
        print("[WARN] Không tìm thấy def api_tool_rules_v2(), sẽ append alias ở cuối file.")
        insert_at = len(data)
    else:
        # tìm hết block hàm api_tool_rules_v2 để chèn sau đó
        insert_at = data.find("\n", idx)
        # nhảy thêm một ít cho chắc
        insert_at = data.find("\n", insert_at + 1)

    block = '''

# Alias API: tool_rules_v2_v2 – tái sử dụng logic của api_tool_rules_v2
@app.route("/api/tool_rules_v2_v2", methods=["GET"])
def api_tool_rules_v2_v2():
    try:
        return api_tool_rules_v2()
    except Exception as e:
        from flask import jsonify
        return jsonify({"status": "error", "error": f"alias v2_v2 failed: {e}"}), 500
'''
    new_data = data[:insert_at] + block + data[insert_at:]
    path.write_text(new_data, encoding="utf-8")
    print("[OK] Đã chèn alias /api/tool_rules_v2_v2 vào app.py.")
PY

echo "[DONE] patch_add_tool_rules_v2_v2_alias.sh hoàn thành."
