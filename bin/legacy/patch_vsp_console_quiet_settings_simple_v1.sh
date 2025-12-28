#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
JS="$ROOT/static/js/vsp_console_patch_v1.js"

echo "[PATCH] Target: $JS"
cp "$JS" "$JS.bak_settings_simple_quiet_$(date +%Y%m%d_%H%M%S)"

python - << 'PY'
from pathlib import Path

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/static/js/vsp_console_patch_v1.js")
txt = p.read_text(encoding="utf-8")

needle = 'console.warn("[VSP_SETTINGS_SIMPLE] Missing element "'
if needle not in txt:
    print("[WARN] Không tìm thấy console.warn cho VSP_SETTINGS_SIMPLE, có thể đã patch trước đó – không sửa gì.")
else:
    txt = txt.replace(needle, '// ' + needle, 1)
    p.write_text(txt, encoding="utf-8")
    print("[OK] Đã comment console.warn VSP_SETTINGS_SIMPLE (missing element).")
PY
