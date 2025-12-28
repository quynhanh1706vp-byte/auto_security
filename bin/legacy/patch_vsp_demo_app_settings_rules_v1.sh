#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"

if [[ ! -f "$APP" ]]; then
  echo "[ERR] Không tìm thấy $APP" >&2
  exit 1
fi

BACKUP="${APP}.bak_settings_rules_$(date +%Y%m%d_%H%M%S)"
cp "$APP" "$BACKUP"
echo "[PATCH] Backup: $BACKUP"

python - << 'PY'
from pathlib import Path
import re

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
txt = p.read_text(encoding="utf-8")
orig = txt

changed = False

# 1) Thêm import blueprint nếu chưa có
if "bp_settings_rules" not in txt:
    # tìm 1 block import từ api.* để chèn ngay sau
    m = re.search(r"from\s+api\.[^\n]+\n", txt)
    if m:
        insert_at = m.end()
        inject = "from api.vsp_settings_rules_v1 import bp_settings_rules\n"
        txt = txt[:insert_at] + inject + txt[insert_at:]
        changed = True
        print("[PATCH] + Thêm import bp_settings_rules")
    else:
        # không tìm được, append cuối file
        txt += "\nfrom api.vsp_settings_rules_v1 import bp_settings_rules\n"
        changed = True
        print("[PATCH] + Append import bp_settings_rules ở cuối file")

# 2) register_blueprint nếu chưa có
if "app.register_blueprint(bp_settings_rules)" not in txt:
    # cố gắng chèn sau các app.register_blueprint khác
    m2 = None
    for m in re.finditer(r"app\.register_blueprint\([^)]+\)\n", txt):
        m2 = m
    if m2:
        insert_at = m2.end()
        inject = "app.register_blueprint(bp_settings_rules)\n"
        txt = txt[:insert_at] + inject + txt[insert_at:]
        changed = True
        print("[PATCH] + Thêm app.register_blueprint(bp_settings_rules)")
    else:
        txt += "\napp.register_blueprint(bp_settings_rules)\n"
        changed = True
        print("[PATCH] + Append app.register_blueprint(bp_settings_rules) ở cuối file")

if changed and txt != orig:
    p.write_text(txt, encoding="utf-8")
    print("[PATCH] Đã ghi lại vsp_demo_app.py")
else:
    print("[PATCH] Không có thay đổi trong vsp_demo_app.py")
PY
