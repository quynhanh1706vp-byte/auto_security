#!/usr/bin/env bash
set -euo pipefail

JS="/home/test/Data/SECURITY_BUNDLE/ui/static/js/vsp_console_patch_v1.js"
echo "[PATCH] Target: $JS"
cp "$JS" "$JS.bak_settings_bind_quiet_$(date +%Y%m%d_%H%M%S)"

python - << 'PY'
from pathlib import Path

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/static/js/vsp_console_patch_v1.js")
txt = p.read_text(encoding="utf-8")

block = '''  if (!window.vspInitSettingsTab) {
    console.warn("[VSP_SETTINGS_BIND] vspInitSettingsTab not found on window.");
    return;
  }
  window.vspInitSettingsTab();'''

if block in txt:
    new_block = '''  if (!window.vspInitSettingsTab) {
    console.log("[VSP_SETTINGS_BIND] vspInitSettingsTab not found – skip.");
    return;
  }
  window.vspInitSettingsTab();'''
    txt = txt.replace(block, new_block)
    p.write_text(txt, encoding="utf-8")
    print("[OK] Đã patch block VSP_SETTINGS_BIND (warn -> log).")
else:
    # fallback: chỉ đổi câu console.warn nếu block hơi khác
    before = 'console.warn("[VSP_SETTINGS_BIND] vspInitSettingsTab not found on window.");'
    after  = 'console.log("[VSP_SETTINGS_BIND] vspInitSettingsTab not found – skip.");'
    if before in txt:
        txt = txt.replace(before, after)
        p.write_text(txt, encoding="utf-8")
        print("[OK] Đã hạ console.warn -> console.log cho VSP_SETTINGS_BIND (fallback).")
    else:
        print("[WARN] Không tìm thấy console.warn VSP_SETTINGS_BIND – không sửa gì.")
PY
