#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_runs_kpi_compact_v3.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_force_v2_${TS}"
echo "[BACKUP] ${JS}.bak_force_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_runs_kpi_compact_v3.js")
s = p.read_text(encoding="utf-8", errors="replace")

# Case 1: exact urls array line exists (as shown in your grep)
s2, n = re.subn(
  r"const\s+urls\s*=\s*\[\s*`/api/ui/runs_kpi_v3b\?days=\$\{q\}`\s*,\s*`/api/ui/runs_kpi_v2\?days=\$\{q\}`\s*,\s*`/api/ui/runs_kpi_v1\?days=\$\{q\}`\s*\]\s*;",
  r"const urls = [`/api/ui/runs_kpi_v2?days=${q}`, `/api/ui/runs_kpi_v1?days=${q}`];",
  s
)

# Case 2: fallback—if file references v3b elsewhere, remove it
if n == 0 and "runs_kpi_v3b" in s2:
    s2 = s2.replace("runs_kpi_v3b", "runs_kpi_v2")
    n = 1

p.write_text(s2, encoding="utf-8")
print(f"[OK] patched compact KPI js (force v2). changes={n}")
PY

node --check "$JS" >/dev/null && echo "[OK] node --check OK"
echo "[DONE] p2_runs_kpi_compact_force_v2_first_v1"
