#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$UI_ROOT/static/js/vsp_console_patch_v1.js"

if [[ ! -f "$TARGET" ]]; then
  echo "[ERR] Không tìm thấy $TARGET"
  exit 1
fi

BACKUP="${TARGET}.bak_use_settings_ui_v1_$(date +%Y%m%d_%H%M%S)"
cp "$TARGET" "$BACKUP"
echo "[BACKUP] $TARGET -> $BACKUP"

python - << 'PY'
import pathlib, os

root = pathlib.Path(os.getcwd())
path = root / "static" / "js" / "vsp_console_patch_v1.js"

txt = path.read_text(encoding="utf-8")

old = "/api/vsp/settings_v1"
new = "/api/vsp/settings_ui_v1"

if old not in txt:
    print("[INFO] Không tìm thấy", old, "trong", path)
else:
    txt = txt.replace(old, new)
    path.write_text(txt, encoding="utf-8")
    print("[PATCH] Đã thay", old, "->", new, "trong", path)
PY

echo "[OK] patch_vsp_console_use_settings_ui_v1 xong."
