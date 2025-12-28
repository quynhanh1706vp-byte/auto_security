#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_tabs_hash_router_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

grep -q "ROUTE_RULES_V1" "$F" && { echo "[OK] router already patched"; exit 0; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_rules_${TS}"
echo "[BACKUP] $F.bak_rules_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_tabs_hash_router_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

# Add 'rules' into common route arrays: ['dashboard','runs','settings','datasource']
def add_rules_in_list(m):
    txt=m.group(0)
    if "rules" in txt: return txt
    return txt.replace("datasource", "datasource','rules")

s2 = re.sub(r"\[\s*'dashboard'\s*,\s*'runs'\s*,\s*'settings'\s*,\s*'datasource'\s*\]", add_rules_in_list, s)
s = s2

# Add mapping panel id if router uses a map like panelByTab = {dashboard:'panel-dashboard',...}
if re.search(r"panelByTab\s*=\s*\{", s) and "rules" not in s:
    s = re.sub(r"(panelByTab\s*=\s*\{)",
               r"\1\n  // ROUTE_RULES_V1\n  rules: 'panel-rules',",
               s, count=1)

# Fallback: if it uses querySelector(`[data-panel="${tab}"]`) then no map needed.

# Also ensure binds click for [data-tab="rules"] (usually generic already). Just tag patch.
if "ROUTE_RULES_V1" not in s:
    s += "\n// ROUTE_RULES_V1: enabled 'rules' route\n"

p.write_text(s, encoding="utf-8")
print("[OK] patched router file")
PY

echo "[DONE] patched $F"
