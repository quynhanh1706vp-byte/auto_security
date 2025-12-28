#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

JS="static/js/vsp_runs_reports_overlay_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_silence_legacy_${TS}"
echo "[BACKUP] ${JS}.bak_silence_legacy_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_runs_reports_overlay_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P2_SILENCE_RUNS_KPI_V1_LEGACY"
if marker in s:
    print("[OK] legacy silence already applied")
    raise SystemExit(0)

# Insert guard right after the opening brace of v1 loadRunsKpi
# This stops v1 KPI updater when panel v1 is gone OR v2 binder exists.
pat = re.compile(r'(async\s+function\s+loadRunsKpi\s*\([^)]*\)\s*\{)', re.M)
m = pat.search(s)
if not m:
    raise SystemExit("[ERR] cannot find async function loadRunsKpi(...) { in JS")

guard = r"""
/* VSP_P2_SILENCE_RUNS_KPI_V1_LEGACY */
try{
  // If KPI v2 exists or v1 panel nodes are missing => skip legacy updater to avoid null.textContent crashes.
  if (window.__vsp_runs_kpi_bind_v2 || document.getElementById("vsp_runs_kpi_panel_v2")) return;
  // legacy v1 panel markers (adjust if you renamed ids)
  const must1 = document.getElementById("vsp_runs_kpi_status") || document.getElementById("vsp_runs_kpi_status_v1");
  if (!must1) return;
}catch(_){ return; }
"""

s2 = s[:m.end()] + "\n" + guard + s[m.end():]

p.write_text(s2, encoding="utf-8")
print("[OK] injected legacy KPI v1 guard")
PY

node --check "$JS" && echo "[OK] node --check OK"
echo "[DONE] p2_runs_kpi_silence_legacy_v1"
