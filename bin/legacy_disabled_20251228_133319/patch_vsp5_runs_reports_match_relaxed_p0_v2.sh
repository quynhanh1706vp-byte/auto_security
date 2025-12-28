#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_relaxed_${TS}"
echo "[BACKUP] ${JS}.bak_relaxed_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP5_RUNS_REPORTS_RELAXED_MATCH_P0_V2"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Replace findRunsTable() in the VSP5 enhancer block to be more tolerant.
pat = r"function findRunsTable\(\)\{\n\s*const tables = qsa\('table'\);\n[\s\S]*?\n\s*return null;\n\s*\}"
m=re.search(pat, s)
if not m:
    raise SystemExit("[ERR] cannot find findRunsTable() to relax")

rep = r"""function findRunsTable(){
    const tables = qsa('table');
    // relaxed: pick first table that has any cell containing RUN_... and at least 1 row in tbody
    for (const t of tables){
      const bodyRows = qsa('tbody tr', t);
      if (!bodyRows.length) continue;
      const sample = bodyRows.slice(0,5).map(tr => (tr.textContent||'')).join(' ');
      if (/RUN[_A-Z0-9.-]{6,}/.test(sample)) return t;
      // fallback by headers containing RUN
      const ths = qsa('thead th', t).map(x=> (x.textContent||'').trim().toUpperCase());
      if (ths.some(x=>x.includes('RUN'))) return t;
    }
    return null;
  }\n  // """ + MARK

s2 = re.sub(pat, rep, s, count=1)
p.write_text(s2, encoding="utf-8")
print("[OK] relaxed matcher patched")
PY

node --check "$JS"
echo "[OK] node --check OK"
sudo systemctl restart vsp-ui-8910.service
sleep 1
echo "[OK] restart done; Ctrl+F5 /vsp5"
