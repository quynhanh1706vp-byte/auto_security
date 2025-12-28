#!/usr/bin/env bash
set -euo pipefail

JS="static/js/vsp_dashboard_enhance_v1.js"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy $JS (đứng ở thư mục ui nhé)."
  exit 1
fi

BAK="$JS.bak_remove_bad_patch_$(date +%Y%m%d_%H%M%S)"
cp "$JS" "$BAK"
echo "[BACKUP] Đã backup $JS -> $BAK"

python - << 'PY'
from pathlib import Path

js = Path("static/js/vsp_dashboard_enhance_v1.js")
txt = js.read_text(encoding="utf-8")

marker = "window.hydrateDashboard = function patchedHydrateDashboard"
idx = txt.find(marker)
if idx == -1:
    print("[INFO] Không thấy đoạn patchedHydrateDashboard, giữ nguyên file.")
else:
    print("[INFO] Tìm thấy đoạn patchedHydrateDashboard, sẽ cắt bỏ mọi thứ từ đoạn đó trở xuống.")
    txt = txt[:idx]
    js.write_text(txt, encoding="utf-8")
    print("[OK] Đã ghi lại file không còn patch hỏng.")
PY
