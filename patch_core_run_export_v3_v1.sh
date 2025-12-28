#!/usr/bin/env bash
set -euo pipefail

APP_CORE="/home/test/Data/SECURITY_BUNDLE/ui/my_flask_app/app.py"

echo "[PATCH] Gắn bp_run_export_v3 vào core my_flask_app/app.py"

python - << 'PY'
from pathlib import Path

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/my_flask_app/app.py")
if not p.is_file():
    print("[PATCH] Không tìm thấy", p)
    raise SystemExit(1)

txt = p.read_text(encoding="utf-8")
orig = txt
changed = False

# 1) Thêm import nếu chưa có
if "from api.vsp_run_export_api_v3 import bp_run_export_v3" not in txt:
    txt += "\n\n# === VSP_RUN_EXPORT_V3: auto import ===\n"
    txt += "from api.vsp_run_export_api_v3 import bp_run_export_v3\n"
    changed = True

# 2) Thêm register blueprint nếu chưa có
if "app.register_blueprint(bp_run_export_v3)" not in txt:
    txt += "\n# === VSP_RUN_EXPORT_V3: auto register ===\n"
    txt += "app.register_blueprint(bp_run_export_v3)\n"
    changed = True

if changed:
    backup = p.with_suffix(p.suffix + ".bak_core_run_export_v3")
    backup.write_text(orig, encoding="utf-8")
    p.write_text(txt, encoding="utf-8")
    print("[PATCH] Đã patch", p, "(backup ->", backup.name, ")")
else:
    print("[PATCH] Không cần patch", p, "(đã có import + register).")
PY

echo "[PATCH] Done."
