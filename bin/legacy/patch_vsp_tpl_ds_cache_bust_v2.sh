#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT/templates/vsp_dashboard_2025.html"

if [ ! -f "$TPL" ]; then
  echo "[DS_CACHE_V2][ERR] Không thấy template $TPL"
  exit 1
fi

BAK="${TPL}.bak_ds_cache_v2_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$BAK"
echo "[DS_CACHE_V2] Backup $TPL -> $BAK"

python - << 'PY'
from pathlib import Path

tpl_path = Path("templates/vsp_dashboard_2025.html")
txt = tpl_path.read_text(encoding="utf-8")

old = "vsp_datasource_tab_simple_v1.js"
new = "vsp_datasource_tab_simple_v1.js?v=v2_ds_20251212"

if old not in txt:
    print("[DS_CACHE_V2][WARN] Không thấy", old, "trong template.")
else:
    txt = txt.replace(old, new)
    tpl_path.write_text(txt, encoding="utf-8")
    print("[DS_CACHE_V2][OK] Đã thay", old, "->", new)
PY
