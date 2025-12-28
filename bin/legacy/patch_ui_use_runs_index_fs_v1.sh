#!/usr/bin/env bash
set -euo pipefail
FILES=(
  "static/js/vsp_tabs_hash_router_v1.js"
  "static/js/vsp_runs_tab_simple_v2.js"
  "static/js/vsp_runs_kpi_reports_v1.js"
  "static/js/vsp_ui_extras_v25.js"
)

TS="$(date +%Y%m%d_%H%M%S)"
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  cp "$f" "$f.bak_runsfs_${TS}"
done
echo "[BACKUP] done"

python3 - << 'PY'
from pathlib import Path
import re

files = [
  Path("static/js/vsp_tabs_hash_router_v1.js"),
  Path("static/js/vsp_runs_tab_simple_v2.js"),
  Path("static/js/vsp_runs_kpi_reports_v1.js"),
  Path("static/js/vsp_ui_extras_v25.js"),
]
for p in files:
  if not p.exists(): 
    continue
  txt = p.read_text(encoding="utf-8", errors="replace")
  txt2 = txt.replace("/api/vsp/runs_index_v3?", "/api/vsp/runs_index_v3_fs?")
  # nếu code dùng string full URL thì thay cả runs_index_v3?limit
  txt2 = txt2.replace("runs_index_v3?limit", "runs_index_v3_fs?limit")
  if txt2 != txt:
    p.write_text(txt2, encoding="utf-8")
    print("[OK] patched", p)
PY
