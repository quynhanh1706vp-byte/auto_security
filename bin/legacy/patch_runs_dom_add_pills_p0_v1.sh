#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_pills_${TS}"
echo "[BACKUP] ${JS}.bak_pills_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_RUNS_DOM_PILLS_P0_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# We patch inside the V4 DOM enhancer block by locating where wrap is created.
if "VSP_RUNS_DOM_ENHANCE_LINKS_P0_V4" not in s:
    raise SystemExit("[ERR] V4 enhancer not found in JS")

# Find the exact snippet:
needle = "const wrap = document.createElement('span');"
i = s.find(needle)
if i < 0:
    raise SystemExit("[ERR] cannot find wrap creation")

# Find where wrap.className is set right after
m = re.search(r"const wrap = document\.createElement\('span'\);\n\s+wrap\.className = 'vsp-open-any';", s[i:])
if not m:
    raise SystemExit("[ERR] cannot find wrap.className assignment near wrap creation")
pos = i + m.end()

inject = r"""
        // VSP_RUNS_DOM_PILLS_P0_V1: add status pills for artifacts
        try{
          const pillWrap=document.createElement('span');
          pillWrap.style.marginLeft='6px';

          function pill(txt, cls){
            const sp=document.createElement('span');
            sp.className='pill '+(cls||'pill-muted');
            sp.textContent=txt;
            return sp;
          }

          // Show compact pills based on link availability (not HEAD-check)
          if (links.json) pillWrap.appendChild(pill('JSON','pill-ok'));
          if (links.html) pillWrap.appendChild(pill('HTML','pill-ok'));
          else pillWrap.appendChild(pill('HTML:-','pill-muted'));

          if (links.summary) pillWrap.appendChild(pill('SUM','pill-ok'));
          else pillWrap.appendChild(pill('SUM:-','pill-warn'));

          if (links.csv) pillWrap.appendChild(pill('CSV','pill-ok'));
          if (links.sarif) pillWrap.appendChild(pill('SARIF','pill-ok'));

          td.appendChild(pillWrap);
        }catch(e){}
"""

s2 = s[:pos] + "\n" + inject + s[pos:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected:", MARK)
PY

node --check "$JS"
echo "[OK] node --check OK"

sudo systemctl restart vsp-ui-8910.service
sleep 0.8

echo "== smoke /runs =="
curl -sS -I http://127.0.0.1:8910/runs | sed -n '1,15p'
echo "[OK] open http://127.0.0.1:8910/runs (or /vsp5) and check pills appear in last column."
