#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE"

echo "[i] ROOT = $ROOT"

# Tìm app.py trong ROOT (tối đa depth=2)
APP=$(find "$ROOT" -maxdepth 2 -type f -name 'app.py' | head -n 1 || true)

if [ -z "$APP" ]; then
  echo "[ERR] Không tìm thấy app.py dưới $ROOT (maxdepth=2)"
  exit 1
fi

echo "[i] APP = $APP"

python3 - "$APP" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

# Nếu đã có route rồi thì bỏ qua
if "def tool_config_json(" in data:
    print("[INFO] app.py đã có tool_config_json – bỏ qua.")
    sys.exit(0)

# Thêm import riêng, không đụng import cũ
prefix = (
    "from flask import jsonify as _sb_jsonify\n"
    "from flask import send_file as _sb_send_file\n"
)

if prefix not in data:
    data = prefix + data

route = """

# === SB: Route phục vụ tool_config.json (dùng cho Dashboard / Settings) ===
@app.route("/tool_config.json")
def tool_config_json():
    from pathlib import Path

    here = Path(__file__).resolve().parent

    candidates = [
        here / "tool_config.json",
        here.parent / "ui" / "tool_config.json",
        here.parent / "tool_config.json",
        Path("/home/test/Data/SECURITY_BUNDLE/ui/tool_config.json"),
    ]

    cfg = None
    for c in candidates:
        if c.is_file():
            cfg = c
            break

    if cfg is None:
        return _sb_jsonify({"error": "tool_config.json not found"}), 404

    return _sb_send_file(str(cfg), mimetype="application/json")
"""

data = data.rstrip() + route + "\\n"
path.write_text(data, encoding="utf-8")
print("[OK] Đã chèn route tool_config_json vào", path)
PY

echo "[DONE] patch_add_tool_config_route_auto.sh hoàn thành."
