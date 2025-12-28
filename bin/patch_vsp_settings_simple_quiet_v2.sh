#!/usr/bin/env bash
set -euo pipefail

JS="/home/test/Data/SECURITY_BUNDLE/ui/static/js/vsp_settings_simple_v1.js"
echo "[PATCH] Target: $JS"
cp "$JS" "$JS.bak_quiet_$(date +%Y%m%d_%H%M%S)"

python - << 'PY'
from pathlib import Path

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/static/js/vsp_settings_simple_v1.js")
txt = p.read_text(encoding="utf-8")

old = "    console.warn('[VSP_SETTINGS_SIMPLE] Missing element ' + id);"
if old not in txt:
    print("[WARN] Không tìm thấy dòng console.warn cụ thể, thử pattern mềm hơn.")
    old2 = "console.warn('[VSP_SETTINGS_SIMPLE] Missing element ' + id);"
    if old2 not in txt:
        print("[WARN] Pattern mềm cũng không có – có thể file đã sửa khác, không đụng.")
    else:
        txt = txt.replace(old2, "// " + old2)
        p.write_text(txt, encoding="utf-8")
        print("[OK] Đã comment console.warn (pattern mềm).")
else:
    txt = txt.replace(old, "    // " + old)
    p.write_text(txt, encoding="utf-8")
    print("[OK] Đã comment console.warn VSP_SETTINGS_SIMPLE (pattern chuẩn).")
PY
