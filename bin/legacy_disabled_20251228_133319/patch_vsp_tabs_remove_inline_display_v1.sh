#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="${TPL}.bak_tabs_display_${TS}"
cp "$TPL" "$BACKUP"
echo "[BACKUP] $TPL -> $BACKUP"

cd "$UI_ROOT"

python - << 'PY'
import re, pathlib

tpl_path = pathlib.Path("templates/vsp_dashboard_2025.html")
txt = tpl_path.read_text(encoding="utf-8")

# Chỉ remove style="display: none;" trên <section> có id="vsp-tab-..."
pattern = r'(<section[^>]*id="vsp-tab-[^"]+"[^>]*?)\s*style="display:\s*none;"'
new_txt, n = re.subn(pattern, r'\1', txt)

print(f"[PATCH] Removed inline display:none on {n} <section id=\"vsp-tab-*\"> tags")
tpl_path.write_text(new_txt, encoding="utf-8")
PY

echo "[DONE] patch_vsp_tabs_remove_inline_display_v1.sh hoàn tất."
