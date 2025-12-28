#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$ROOT/static/js/vsp_console_patch_v1.js"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy $JS"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp "$JS" "${JS}.bak_tabs_silence_${TS}"
echo "[BACKUP] $JS -> ${JS}.bak_tabs_silence_${TS}"

python3 - << 'PY'
from pathlib import Path

p = Path("static/js/vsp_console_patch_v1.js")
txt = p.read_text(encoding="utf-8")

marker = 'No tab buttons or panes found – skip.'
if marker not in txt:
    print("[INFO] Không thấy dòng log cũ, bỏ qua.")
else:
    txt_new = txt.replace('log("No tab buttons or panes found – skip.', '// log("No tab buttons or panes found – skip.')
    p.write_text(txt_new, encoding="utf-8")
    print("[OK] Đã comment dòng log [VSP_TABS] cũ.")
PY
