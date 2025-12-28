#!/usr/bin/env bash
set -euo pipefail

echo "[PATCH] Đăng ký bp_run_export_v3 cho cả vsp_demo_app.py và my_flask_app/app.py"

python - << 'PY'
from pathlib import Path

ROOT = Path("/home/test/Data/SECURITY_BUNDLE/ui")

files = [
    ROOT / "vsp_demo_app.py",
    ROOT / "my_flask_app" / "app.py",
]

for p in files:
    if not p.is_file():
        print("[PATCH] (skip) không thấy", p)
        continue

    txt = p.read_text(encoding="utf-8")
    changed = False

    if "from api.vsp_run_export_api_v3 import bp_run_export_v3" not in txt:
        txt += "\n\n# === VSP_RUN_EXPORT_V3 auto import ===\n"
        txt += "from api.vsp_run_export_api_v3 import bp_run_export_v3\n"
        changed = True

    if "app.register_blueprint(bp_run_export_v3)" not in txt:
        txt += "\n# === VSP_RUN_EXPORT_V3 auto register ===\n"
        txt += "app.register_blueprint(bp_run_export_v3)\n"
        changed = True

    if changed:
        backup = p.with_suffix(p.suffix + ".bak_run_export_both")
        backup.write_text(p.read_text(encoding="utf-8"), encoding="utf-8")
        p.write_text(txt, encoding="utf-8")
        print("[PATCH] Đã patch", p, "(backup ->", backup.name, ")")
    else:
        print("[PATCH] Không cần patch", p, "(đã có import + register).")
PY

echo "[PATCH] Done."
