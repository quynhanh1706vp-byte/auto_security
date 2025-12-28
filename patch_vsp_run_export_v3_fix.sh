#!/usr/bin/env bash
set -euo pipefail

APP_PY="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"

echo "[PATCH] Fix register bp_run_export_v3 trong vsp_demo_app.py"

python - << 'PY'
from pathlib import Path

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
txt = p.read_text(encoding="utf-8")

need_import = "from api.vsp_run_export_api_v3 import bp_run_export_v3" not in txt
need_reg    = "app.register_blueprint(bp_run_export_v3)" not in txt

if not (need_import or need_reg):
    print("[PATCH] Import + register đã có sẵn, không làm gì.")
else:
    backup = p.with_suffix(p.suffix + ".bak_run_export_fix")
    backup.write_text(txt, encoding="utf-8")
    print("[PATCH] Backup ->", backup.name)

    extra_lines = []
    if need_import:
        extra_lines.append("from api.vsp_run_export_api_v3 import bp_run_export_v3")
    if need_reg:
        extra_lines.append("app.register_blueprint(bp_run_export_v3)")

    extra_block = "\n\n# === VSP_RUN_EXPORT_V3 auto patch ===\n" + "\n".join(extra_lines) + "\n"

    txt = txt + extra_block
    p.write_text(txt, encoding="utf-8")
    print("[PATCH] Đã append import/register cho bp_run_export_v3.")
PY

echo "[PATCH] Done."
