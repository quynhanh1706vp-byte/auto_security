#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/app.py"

echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy app.py"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

if "def tool_config_json(" in data:
    print("[INFO] app.py đã có route tool_config_json – bỏ qua.")
    sys.exit(0)

# Đảm bảo có import jsonify & send_file
if "from flask import jsonify" not in data:
    # chèn thêm một dòng import riêng, không đụng vào import cũ
    data = "from flask import jsonify\n" + data

if "from flask import send_file" not in data:
    data = "from flask import send_file\n" + data

route = """

# === Route phục vụ tool_config.json (UI dùng để build bảng BY TOOL) ===
@app.route("/tool_config.json")
def tool_config_json():
    from pathlib import Path
    cfg = Path(__file__).resolve().parent / "tool_config.json"
    # Nếu không có ở thư mục ui/, thử tìm ở thư mục cha
    if not cfg.is_file():
        root = Path(__file__).resolve().parent.parent
        alt = root / "tool_config.json"
        if alt.is_file():
            cfg = alt
        else:
            return jsonify({"error": "tool_config.json not found"}), 404
    return send_file(str(cfg), mimetype="application/json")
"""

# Thêm route vào cuối file
data = data.rstrip() + route + "\n"
path.write_text(data, encoding="utf-8")
print("[OK] Đã chèn route tool_config_json vào app.py")
PY

echo "[DONE] patch_add_tool_config_route.sh hoàn thành."
