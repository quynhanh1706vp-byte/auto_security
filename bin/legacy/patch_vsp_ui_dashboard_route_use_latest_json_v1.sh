#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
APP="$UI_ROOT/vsp_demo_app.py"

if [ ! -f "$APP" ]; then
  echo "[PATCH_UI_DASH_ROUTE][ERR] Không tìm thấy $APP"
  exit 1
fi

BACKUP="${APP}.bak_ui_dashboard_route_$(date +%Y%m%d_%H%M%S)"
cp "$APP" "$BACKUP"
echo "[PATCH_UI_DASH_ROUTE] Backup -> $BACKUP"

export UI_ROOT

python - << 'PY'
import os, pathlib, re, sys

LOG_PREFIX = "[PATCH_UI_DASH_ROUTE_PY]"
ui_root = pathlib.Path(os.environ["UI_ROOT"])
app_path = ui_root / "vsp_demo_app.py"

txt = app_path.read_text(encoding="utf-8")

if "VSP_UI_DASHBOARD_V3_LATEST_JSON_PATCH" in txt:
    print(LOG_PREFIX, "Đã có patch trong file, bỏ qua.")
    sys.exit(0)

m = re.search(r"def\s+([a-zA-Z0-9_]*dashboard_v3)\s*\([^)]*\):", txt)
if not m:
    print(LOG_PREFIX, "[ERR] Không tìm thấy hàm *dashboard_v3 trong vsp_demo_app.py")
    sys.exit(1)

fn_name = m.group(1)
print(LOG_PREFIX, "Tìm thấy hàm:", fn_name)

idx = txt.find("\n", m.end())
if idx == -1:
    print(LOG_PREFIX, "[ERR] Không xác định được vị trí chèn sau def.")
    sys.exit(1)

inject = r'''
    # [VSP_UI_DASHBOARD_V3_LATEST_JSON_PATCH] Ưu tiên đọc file out/vsp_dashboard_v3_latest.json nếu tồn tại
    try:
        import json, pathlib
        from flask import jsonify
        ui_root = pathlib.Path(__file__).resolve().parent
        root = ui_root.parent  # /home/test/Data/SECURITY_BUNDLE
        latest_path = root / "out" / "vsp_dashboard_v3_latest.json"
        if latest_path.is_file():
            model = json.loads(latest_path.read_text(encoding="utf-8"))
            return jsonify(model)
    except Exception as e:  # noqa: E722
        try:
            from flask import current_app
            current_app.logger.warning("VSP_UI_DASHBOARD_V3_LATEST_JSON_PATCH failed: %r", e)
        except Exception:
            print("VSP_UI_DASHBOARD_V3_LATEST_JSON_PATCH failed:", repr(e))
'''

new_txt = txt[:idx+1] + inject + txt[idx+1:]
app_path.write_text(new_txt, encoding="utf-8")

print(LOG_PREFIX, "Đã chèn patch vào hàm", fn_name)
PY

echo "[PATCH_UI_DASH_ROUTE] Hoàn tất."
