#!/usr/bin/env bash
set -euo pipefail

APP="app.py"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy app.py trong $(pwd)"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, pathlib, textwrap

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

# Nếu đã patch V2 rồi thì thôi
if "SB_FINAL_ROUTES_V2" in data:
    print("[INFO] SB_FINAL_ROUTES_V2 đã có trong app.py – bỏ qua.")
    raise SystemExit(0)

block = textwrap.dedent("""
# ==== SB_FINAL_ROUTES_V2 ====
from flask import jsonify, send_file
from pathlib import Path as _SB_Path

def _sb_find_tool_config():
    candidates = [
        _SB_Path(__file__).resolve().parent / "tool_config.json",
        _SB_Path(__file__).resolve().parent.parent / "ui" / "tool_config.json",
        _SB_Path("/home/test/Data/SECURITY_BUNDLE/ui/tool_config.json"),
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
    cfg = _sb_find_tool_config()
    if cfg is None:
        return jsonify({"error": "tool_config.json not found"}), 404
    return send_file(str(cfg), mimetype="application/json")

@app.route("/scan_one")
def sb_scan_one():
    \"\"\"Run-one-project page.\"\"\"
    ctx = {}
    try:
        if "_sb_build_dashboard_data_ctx" in globals():
            ctx = _sb_build_dashboard_data_ctx()
    except Exception as e:
        print("[SB][scan_one] context error:", e)
    return render_template("scan_one.html", **ctx)
# ==== END SB_FINAL_ROUTES_V2 ====
""")

data = data + block
path.write_text(data, encoding="utf-8")
print("[OK] Đã chèn SB_FINAL_ROUTES_V2 vào", path)
PY

echo "[DONE] patch_fix_routes_final_v2.sh hoàn thành."
