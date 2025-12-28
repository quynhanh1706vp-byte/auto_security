#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/js/vsp_tabs_hash_router_v1.js"

if [ ! -f "$JS" ]; then
  echo "[ROUTER_DS_V2][ERR] Không thấy $JS"
  exit 1
fi

BAK="${JS}.bak_ds_delegate_v2_$(date +%Y%m%d_%H%M%S)"
cp "$JS" "$BAK"
echo "[ROUTER_DS_V2] Backup $JS -> $BAK"

python - << 'PY'
from pathlib import Path
import re

path = Path("static/js/vsp_tabs_hash_router_v1.js")
txt = path.read_text(encoding="utf-8")

m = re.search(r"function renderDatasourcePane\s*\([^)]*\)\s*\{[\s\S]*?\n\}", txt)
if not m:
    print("[ROUTER_DS_V2][ERR] Không tìm thấy function renderDatasourcePane")
else:
    new_block = """function renderDatasourcePane(json) {
  console.log('[VSP_TABS_ROUTER_V1] Datasource pane delegated to V2 widget.');
  if (window.vspInitDatasourceTab) {
    try {
      window.vspInitDatasourceTab();
    } catch (e) {
      console.error('[VSP_TABS_ROUTER_V1] vspInitDatasourceTab error:', e);
    }
  } else {
    console.warn('[VSP_TABS_ROUTER_V1] vspInitDatasourceTab không tồn tại – dùng layout simple mặc định.');
  }
}
"""
    txt2 = txt[:m.start()] + new_block + txt[m.end():]
    path.write_text(txt2, encoding="utf-8")
    print("[ROUTER_DS_V2][OK] Đã thay body của renderDatasourcePane() bằng bản delegate V2.")
PY
