#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$UI_ROOT/static/js/vsp_runs_fullscan_panel_v1.js"

if [[ ! -f "$TARGET" ]]; then
  echo "[ERR] Không tìm thấy $TARGET"
  exit 1
fi

BACKUP="${TARGET}.bak_use_settings_ui_v1_$(date +%Y%m%d_%H%M%S)"
cp "$TARGET" "$BACKUP"
echo "[BACKUP] $TARGET -> $BACKUP"

python - << 'PY'
import pathlib, os

path = pathlib.Path(os.environ.get("VSP_RUNS_FULLSCAN_JS", "static/js/vsp_runs_fullscan_panel_v1.js"))
if not path.is_absolute():
    path = pathlib.Path(os.getcwd()) / path

txt = path.read_text(encoding="utf-8")
new = txt.replace('/api/vsp/settings_v1', '/api/vsp/settings_ui_v1')
path.write_text(new, encoding="utf-8")
print("[PATCH] Đã thay URL settings_v1 -> settings_ui_v1 trong", path)
PY

echo "[OK] patch_vsp_runs_fullscan_use_settings_ui_v1 xong."
