#!/usr/bin/env bash
set -euo pipefail

APP="vsp_demo_app.py"
BACKUP="${APP}.bak_add_github_mode_$(date +%Y%m%d_%H%M%S)"

cp "$APP" "$BACKUP"
echo "[BACKUP] $BACKUP"

python3 << 'PY'
from pathlib import Path

app = Path("vsp_demo_app.py")
txt = app.read_text(encoding="utf-8")

needle = '{"local": "LOCAL_UI",'
if "github_ci" in txt:
    print("[PATCH] github_ci mode đã tồn tại, bỏ qua.")
else:
    if needle not in txt:
        print("[PATCH][WARN] Không tìm thấy block mode mapping, không sửa được tự động.")
    else:
        new_block = '{"local": "LOCAL_UI",\n        "gitlab_ci": "GITLAB_UI",\n        "jenkins_ci": "JENKINS_UI",\n        "github_ci": "GITHUB_UI",'
        txt = txt.replace(needle, new_block)
        app.write_text(txt, encoding="utf-8")
        print("[PATCH] Đã thêm github_ci -> GITHUB_UI.")
PY

echo "[OK] Done."
