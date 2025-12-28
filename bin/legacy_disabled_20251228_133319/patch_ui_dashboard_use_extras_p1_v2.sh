#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_dash_extras_v2_${TS}" && echo "[BACKUP] $F.bak_dash_extras_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_DASHBOARD_USE_EXTRAS_P1_V2"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

ins = r'''
  // === VSP_DASHBOARD_USE_EXTRAS_P1_V2 ===
  function fetchDashboardExtras(rid){
    const u = `/api/vsp/dashboard_v3_extras_v1?rid=${encodeURIComponent(rid||"")}`;
    return fetch(u, {cache:"no-store"})
      .then(r => r.ok ? r.json() : null)
      .then(j => (j && j.ok && j.kpi) ? j.kpi : null)
      .catch(_ => null);
  }

  function setTextSafe(id, val){
    try{
      const el = document.getElementById(id);
      if(!el) return false;
      el.textContent = (val===null || val===undefined) ? "N/A" : String(val);
      return true;
    }catch(_){ return false; }
  }

  function applyKpiExtrasToDom(kpi){
    if(!kpi) return;
    // try common ids (non-breaking if missing)
    setTextSafe("kpi-total", kpi.total);
    setTextSafe("kpi-score", kpi.score);
    setTextSafe("kpi-effective", kpi.effective);
    setTextSafe("kpi-degraded", kpi.degraded);

    // also try a few other likely ids used in your UI patches
    setTextSafe("kpi-total-findings", kpi.total);
    setTextSafe("kpi-effective-findings", kpi.effective);
    setTextSafe("kpi-degraded-findings", kpi.degraded);
  }
  // === /VSP_DASHBOARD_USE_EXTRAS_P1_V2 ===
'''

if "'use strict';" in s:
    s = s.replace("'use strict';", "'use strict';\n"+ins, 1)
else:
    s = ins + s

# Hook: after rid is computed the first time, call fetchDashboardExtras(rid).then(apply...)
# We match first occurrence of "const rid =" (or "let rid =")
hooked = False
for pat in [r'(const\s+rid\s*=\s*[^;]+;\s*\n)',
            r'(let\s+rid\s*=\s*[^;]+;\s*\n)']:
    m = re.search(pat, s)
    if m:
        repl = m.group(1) + '    fetchDashboardExtras(rid).then(applyKpiExtrasToDom);\n'
        s = s[:m.start()] + repl + s[m.end():]
        hooked = True
        break

if not hooked:
    # fallback: hook near a known function name if exists
    s = s.replace("function renderKpis(", "function renderKpis(\n    fetchDashboardExtras(window.__VSP_RID__||'').then(applyKpiExtrasToDom);\n", 1)

p.write_text(s, encoding="utf-8")
print("[OK] patched:", marker, "hooked=", hooked)
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] Hard refresh Ctrl+Shift+R"
