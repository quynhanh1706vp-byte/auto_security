#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
JS="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_strip_${TS}"
echo "[BACKUP] ${JS}.bak_strip_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_RUNS_ACTIONS_STRIP_P0_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Replace the current wrap creation to add a container class + compact spacing.
# We search for: wrap.className = 'vsp-open-any';
s2 = s.replace(
    "wrap.className = 'vsp-open-any';",
    "wrap.className = 'vsp-open-any vsp-actions-strip';\n        // VSP_RUNS_ACTIONS_STRIP_P0_V1"
)

p.write_text(s2, encoding="utf-8")
print("[OK] patched actions strip marker")
PY

node --check "$JS"
echo "[OK] node --check OK"
sudo systemctl restart vsp-ui-8910.service
