#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$ROOT/static/js/vsp_console_patch_v1.js"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy $JS"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp "$JS" "${JS}.bak_tabs_log_${TS}"
echo "[BACKUP] $JS -> ${JS}.bak_tabs_log_${TS}"

python3 - << 'PY'
from pathlib import Path
p = Path("static/js/vsp_console_patch_v1.js")
txt = p.read_text(encoding="utf-8")

needle = 'No tab buttons or panes found \u2013 skip.'
if needle not in txt:
    # fallback: cứ comment mọi dòng chứa "No tab buttons or panes found"
    import re
    txt_new = re.sub(r'.*No tab buttons or panes found.*\\n', '// [VSP_TABS] log removed by patch\\n', txt)
    if txt_new != txt:
        p.write_text(txt_new, encoding="utf-8")
        print("[OK] Đã xoá log [VSP_TABS] bằng regex fallback.")
    else:
        print("[INFO] Không tìm thấy log [VSP_TABS], bỏ qua.")
else:
    txt = txt.replace(needle, "log removed")
    p.write_text(txt, encoding="utf-8")
    print("[OK] Đã chỉnh sửa chuỗi log [VSP_TABS].")
PY
