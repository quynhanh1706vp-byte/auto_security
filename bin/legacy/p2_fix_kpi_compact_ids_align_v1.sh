#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_runs_kpi_compact_v3.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_align_ids_${TS}"
echo "[BACKUP] ${JS}.bak_align_ids_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_runs_kpi_compact_v3.js")
s = p.read_text(encoding="utf-8", errors="replace")

repls = [
  ("vsp_runs_kpi_green_window", "vsp_runs_kpi_GREEN"),
  ("vsp_runs_kpi_amber_window", "vsp_runs_kpi_AMBER"),
  ("vsp_runs_kpi_red_window", "vsp_runs_kpi_RED"),
  ("vsp_runs_kpi_unknown_window", "vsp_runs_kpi_UNKNOWN"),
  ("vsp_runs_kpi_has_findings_window", "vsp_runs_kpi_findings"),
  ("vsp_runs_kpi_latest_rid", "vsp_runs_kpi_latest"),
]

n = 0
for a,b in repls:
  if a in s:
    s = s.replace(a,b)
    n += 1

p.write_text(s, encoding="utf-8")
print(f"[OK] replaced id mappings: {n}/{len(repls)}")
PY

node --check "$JS"
echo "[OK] node --check OK"
echo "[DONE] Now hard-reload /runs (Ctrl+Shift+R). KPI should populate."
