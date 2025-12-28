#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE"

# Tìm app.py trong ROOT (depth <=2)
APP=$(find "$ROOT" -maxdepth 2 -type f -name 'app.py' | head -n 1 || true)

if [ -z "$APP" ]; then
  echo "[ERR] Không tìm thấy app.py dưới $ROOT"
  exit 1
fi

echo "[i] APP = $APP"

python3 - "$APP" <<'PY'
import sys, pathlib, textwrap

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

if "SB_TOOL_CONFIG_ROUTES_V1" in data:
    print("[INFO] Đã có block SB_TOOL_CONFIG_ROUTES_V1 – bỏ qua.")
    sys.exit(0)

# Đảm bảo có import jsonify / send_file
if "from flask import jsonify" not in data:
    data = "from flask import jsonify\n" + data

if "from flask import send_file" not in data:
    data = "from flask import send_file\n" + data

block = textwrap.dedent("""
# ==== SB_TOOL_CONFIG_ROUTES_V1 ====
from pathlib import Path as _SB_TC_Path

def _sb_tc_find_cfg():
    candidates = [
        _SB_TC_Path(__file__).resolve().parent / "tool_config.json",
        _SB_TC_Path(__file__).resolve().parent.parent / "ui" / "tool_config.json",
        _SB_TC_Path("/home/test/Data/SECURITY_BUNDLE/ui/tool_config.json"),
    ]
    for c in candidates:
        if c.is_file():
            return c
    return None

@app.route("/tool_config.json")
@app.route("/ui/tool_config.json")
@app.route("/config/tool_config.json")
@app.route("/data/tool_config.json")
def sb_tool_config_json_all():
    cfg = _sb_tc_find_cfg()
    if cfg is None:
        return jsonify({"error": "tool_config.json not found"}), 404
    return send_file(str(cfg), mimetype="application/json")
# ==== END SB_TOOL_CONFIG_ROUTES_V1 ====
""")

data = data + block
path.write_text(data, encoding="utf-8")
print("[OK] Đã chèn SB_TOOL_CONFIG_ROUTES_V1 vào", path)
PY

echo "[DONE] patch_tool_config_routes_full.sh hoàn thành."
