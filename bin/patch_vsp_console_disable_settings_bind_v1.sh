#!/usr/bin/env bash
set -euo pipefail

JS="/home/test/Data/SECURITY_BUNDLE/ui/static/js/vsp_console_patch_v1.js"
echo "[PATCH] Target: $JS"
cp "$JS" "$JS.bak_settings_bind_disabled_$(date +%Y%m%d_%H%M%S)"

python - << 'PY'
from pathlib import Path

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/static/js/vsp_console_patch_v1.js")
txt = p.read_text(encoding="utf-8")

old = '''function bindVspSettingsTab() {
    if (!window.vspInitSettingsTab) {
      console.log(LOG, "vspInitSettingsTab not found – skip.");
      return;
    }'''
new = '''function bindVspSettingsTab() {
    // Legacy autobind Settings không còn dùng nữa – bỏ qua cho console sạch.
    return;
}'''

if old not in txt:
    print("[WARN] Block bindVspSettingsTab() kiểu mới không khớp, thử pattern warn cũ...")
    old2 = '''function bindVspSettingsTab() {
    if (!window.vspInitSettingsTab) {
      console.warn(LOG, "vspInitSettingsTab not found on window.");
      return;
    }'''
    if old2 not in txt:
        print("[ERR] Không tìm thấy block bindVspSettingsTab() cần patch – stop.")
        raise SystemExit(1)
    txt = txt.replace(old2, new)
else:
    txt = txt.replace(old, new)

p.write_text(txt, encoding="utf-8")
print("[OK] Đã biến bindVspSettingsTab() thành no-op (không log, không làm gì).")
PY
