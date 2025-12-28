#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$UI_ROOT/static/js/vsp_settings_tab_v1.js"

if [[ ! -f "$TARGET" ]]; then
  echo "[ERR] Không tìm thấy $TARGET"
  exit 1
fi

BACKUP="${TARGET}.bak_use_settings_ui_v1_$(date +%Y%m%d_%H%M%S)"
cp "$TARGET" "$BACKUP"
echo "[BACKUP] $TARGET -> $BACKUP"

# Thay mọi chỗ dùng /api/vsp/settings_v1 thành /api/vsp/settings_ui_v1
python - << 'PY'
import pathlib, os

path = pathlib.Path(os.environ.get("VSP_SETTINGS_TAB_JS", "static/js/vsp_settings_tab_v1.js"))
# path relative đã set ở shell, nhưng để chắc chắn:
if not path.is_absolute():
    path = pathlib.Path(os.getcwd()) / path

txt = path.read_text(encoding="utf-8")
new = txt.replace('/api/vsp/settings_v1', '/api/vsp/settings_ui_v1')
path.write_text(new, encoding="utf-8")
print("[PATCH] Đã thay URL settings_v1 -> settings_ui_v1 trong", path)
PY

echo "[OK] patch_vsp_settings_tab_use_settings_ui_v1 xong."
