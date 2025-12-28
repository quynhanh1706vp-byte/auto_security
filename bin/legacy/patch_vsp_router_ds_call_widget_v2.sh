#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/js/vsp_tabs_hash_router_v1.js"

if [ ! -f "$JS" ]; then
  echo "[ROUTER_DS_V2][ERR] Không thấy $JS"
  exit 1
fi

BAK="${JS}.bak_ds_call_widget_v2_$(date +%Y%m%d_%H%M%S)"
cp "$JS" "$BAK"
echo "[ROUTER_DS_V2] Backup $JS -> $BAK"

python - << 'PY'
from pathlib import Path
import re

path = Path("static/js/vsp_tabs_hash_router_v1.js")
txt = path.read_text(encoding="utf-8")

pattern = r"(console\.log\('\[VSP_TABS_ROUTER_V1\] Datasource pane hydrated[^;]*;)"
m = re.search(pattern, txt)
if not m:
    print("[ROUTER_DS_V2][ERR] Không tìm thấy log 'Datasource pane hydrated' để móc thêm.")
else:
    orig = m.group(1)
    inject = orig + """
  if (window.vspInitDatasourceTab) {
    try { window.vspInitDatasourceTab(); }
    catch (e) {
      console.error('[VSP_TABS_ROUTER_V1] vspInitDatasourceTab error:', e);
    }
  }"""
    txt = txt[:m.start(1)] + inject + txt[m.end(1):]
    path.write_text(txt, encoding="utf-8")
    print("[ROUTER_DS_V2][OK] Đã chèn call vspInitDatasourceTab() sau log Datasource pane hydrated.")
PY
