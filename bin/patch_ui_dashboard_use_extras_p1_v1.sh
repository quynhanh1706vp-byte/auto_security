#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_dash_extras_${TS}" && echo "[BACKUP] $F.bak_dash_extras_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_DASHBOARD_USE_EXTRAS_P1_V1"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

# inject helper fetchDashboardExtras(rid)
ins = r'''
  // === VSP_DASHBOARD_USE_EXTRAS_P1_V1 ===
  async function fetchDashboardExtras(rid){
    try{
      const u = `/api/vsp/dashboard_v3_extras_v1?rid=${encodeURIComponent(rid||"")}`;
      const r = await fetch(u, {cache:"no-store"});
      if(!r.ok) return null;
      const j = await r.json();
      if(j && j.ok && j.kpi) return j.kpi;
    }catch(_){}
    return null;
  }
  // === /VSP_DASHBOARD_USE_EXTRAS_P1_V1 ===
'''

if "'use strict';" in s:
    s = s.replace("'use strict';", "'use strict';\n"+ins, 1)
else:
    s = ins + s

# Hook: find place where KPI is computed / written; we add an early override:
# We'll look for "async function refresh" or "async function load" in dashboard enhance file
m = re.search(r'async function\s+(refresh|load|render)[^{]*\{', s)
if not m:
    raise SystemExit("[ERR] cannot find main async function in dashboard enhance file")

# insert just after rid is known: after "const rid =" or "rid =" first occurrence
s2 = re.sub(
    r'(const\s+rid\s*=\s*[^;]+;\s*\n)',
    r'\1    const kpiExtras = await fetchDashboardExtras(rid);\n'
    r'    if(kpiExtras){\n'
    r'      window.__VSP_KPI_EXTRAS = kpiExtras;\n'
    r'    }\n',
    s,
    count=1
)
if s2 == s:
    # fallback insert near top of function body
    s2 = s

# Replace N/A writing: if extras exists, use it
# best-effort: update common ids if present
repls = {
  'setText("kpi-total",': 'setText("kpi-total", (window.__VSP_KPI_EXTRAS?.total ?? ',
}
# (keep safe: no risky global replace)
p.write_text(s2, encoding="utf-8")
print("[OK] injected extras fetch (you may still need to wire KPI ids depending on template)")
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] Hard refresh Ctrl+Shift+R"
