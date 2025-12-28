#!/usr/bin/env bash
set -euo pipefail

JS="/home/test/Data/SECURITY_BUNDLE/ui/static/js/vsp_console_patch_v1.js"
echo "[PATCH] Target: $JS"
cp "$JS" "$JS.bak_settings_bind_quiet_$(date +%Y%m%d_%H%M%S)"

python - << 'PY'
from pathlib import Path

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/static/js/vsp_console_patch_v1.js")
txt = p.read_text(encoding="utf-8")

before = '      console.warn(LOG, "vspInitSettingsTab not found on window.");'
after  = '      console.log(LOG, "vspInitSettingsTab not found – skip.");'

if before not in txt:
    print("[WARN] Không tìm thấy dòng console.warn(LOG, ...) – không sửa gì.")
else:
    txt = txt.replace(before, after)
    p.write_text(txt, encoding="utf-8")
    print("[OK] Đã đổi console.warn -> console.log cho VSP_SETTINGS_BIND.")
PY
