#!/usr/bin/env bash
set -euo pipefail

# Sửa trong template dashboard (nơi có inline script Run now)
TPL="/home/test/Data/SECURITY_BUNDLE/ui/templates/vsp_dashboard_2025.html"

if [[ -f "$TPL" ]]; then
  BAK="${TPL}.bak_runfull_$(date +%Y%m%d_%H%M%S)"
  cp "$TPL" "$BAK"
  echo "[PATCH] Backup: $BAK"
  python - << 'PY'
from pathlib import Path
p = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates/vsp_dashboard_2025.html")
txt = p.read_text(encoding="utf-8")
if "/api/vsp/run_full_ext" in txt:
    txt = txt.replace("/api/vsp/run_full_ext", "/api/vsp/run_full_scan")
    p.write_text(txt, encoding="utf-8")
    print("[PATCH] Đã đổi /api/vsp/run_full_ext -> /api/vsp/run_full_scan trong vsp_dashboard_2025.html")
else:
    print("[PATCH] Không thấy /api/vsp/run_full_ext trong vsp_dashboard_2025.html, bỏ qua.")
PY
else
  echo "[WARN] Không tìm thấy template vsp_dashboard_2025.html, bỏ qua."
fi

# Nếu sau này có file JS riêng cho run_fullscan, cũng patch tương tự cho chắc
JS="/home/test/Data/SECURITY_BUNDLE/ui/static/js/vsp_run_fullscan_v1.js"
if [[ -f "$JS" ]]; then
  BAKJS="${JS}.bak_runfull_$(date +%Y%m%d_%H%M%S)"
  cp "$JS" "$BAKJS"
  echo "[PATCH] Backup JS: $BAKJS"
  python - << 'PY'
from pathlib import Path
p = Path("/home/test/Data/SECURITY_BUNDLE/ui/static/js/vsp_run_fullscan_v1.js")
txt = p.read_text(encoding="utf-8")
if "/api/vsp/run_full_ext" in txt:
    txt = txt.replace("/api/vsp/run_full_ext", "/api/vsp/run_full_scan")
    p.write_text(txt, encoding="utf-8")
    print("[PATCH] Đã đổi /api/vsp/run_full_ext -> /api/vsp/run_full_scan trong vsp_run_fullscan_v1.js")
else:
    print("[PATCH] Không thấy /api/vsp/run_full_ext trong vsp_run_fullscan_v1.js, bỏ qua.")
PY
fi

echo "[PATCH] Done."
