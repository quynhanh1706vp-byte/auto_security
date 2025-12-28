#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT/templates/vsp_dashboard_2025.html"

if [ ! -f "$TPL" ]; then
  echo "[PATCH][ERR] Không tìm thấy template: $TPL"
  echo "=> Nếu bạn dùng template khác (vsp_5tabs_full.html), sửa biến TPL trong script."
  exit 1
fi

BK="${TPL}.bak_runscan_ui_v1_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$BK"
echo "[BACKUP] $BK"

python3 - << 'PY'
from pathlib import Path

tpl = Path("templates/vsp_dashboard_2025.html")
txt = tpl.read_text(encoding="utf-8", errors="ignore")

tag = '<script src="/static/js/vsp_runs_trigger_scan_ui_v1.js" defer></script>'

if tag in txt:
    print("[PATCH] Script tag đã tồn tại, bỏ qua.")
else:
    if "</body>" in txt:
        txt = txt.replace("</body>", f"  {tag}\n</body>")
        tpl.write_text(txt, encoding="utf-8")
        print("[PATCH] Đã gắn script RunScan UI vào template.")
    else:
        raise SystemExit("[PATCH][ERR] Không tìm thấy </body> để chèn script.")
PY
