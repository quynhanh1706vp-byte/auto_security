#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_FILE="$UI_ROOT/vsp_demo_app.py"

if [ ! -f "$APP_FILE" ]; then
  echo "[ERR] Không tìm thấy $APP_FILE"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp "$APP_FILE" "${APP_FILE}.bak_rule_rename_${TS}"
echo "[BACKUP] $APP_FILE -> ${APP_FILE}.bak_rule_rename_${TS}"

python3 - << 'PY'
from pathlib import Path
import re

app_path = Path("vsp_demo_app.py")
text = app_path.read_text(encoding="utf-8")

orig_route = '@app.route("/api/vsp/rule_overrides_v1", methods=["GET", "POST"])'
new_route  = '@app.route("/api/vsp/rule_overrides_v1", methods=["GET", "POST"], endpoint="vsp_rule_overrides_v1_api_ui")'

if orig_route in text:
    text = text.replace(orig_route, new_route, 1)
    print("[OK] Đã sửa decorator route đầu tiên cho rule_overrides_v1.")
else:
    print("[WARN] Không tìm thấy decorator route đúng mẫu, thử dùng regex.")
    pattern = r'@app\\.route\\("/api/vsp/rule_overrides_v1",\\s*methods=\\["GET",\\s*"POST"\\]\\)'
    text, n = re.subn(pattern, new_route, text, count=1)
    if n:
        print("[OK] Đã sửa decorator bằng regex.")
    else:
        print("[ERR] Không sửa được decorator route – kiểm tra file vsp_demo_app.py.")

# Đổi tên function nếu còn dùng tên cũ
if "def vsp_rule_overrides_v1_api_ui(" not in text and "def vsp_rule_overrides_v1_api(" in text:
    text = text.replace("def vsp_rule_overrides_v1_api(", "def vsp_rule_overrides_v1_api_ui(", 1)
    print("[OK] Đã đổi tên function đầu tiên vsp_rule_overrides_v1_api -> vsp_rule_overrides_v1_api_ui.")
else:
    print("[INFO] Function name đã khác hoặc không tìm thấy vsp_rule_overrides_v1_api.")

app_path.write_text(text, encoding="utf-8")
PY
