#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_kpi_lock_${TS}" && echo "[BACKUP] $F.bak_kpi_lock_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_ui_4tabs_commercial_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_KPI_LOCK_PREFER_EXTRAS_P1_V1"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

# inject helpers after 'use strict';
ins = r'''
  // === VSP_KPI_LOCK_PREFER_EXTRAS_P1_V1 ===
  function _vspKpiEl(id){ try{return document.getElementById(id);}catch(_){return null;} }
  function _vspKpiHasValue(el){
    try{
      const t = (el && (el.textContent||"") || "").trim();
      if(!t) return false;
      const u = t.toUpperCase();
      return (t !== "…" && t !== "—" && u !== "N/A");
    }catch(_){ return false; }
  }
  function _vspKpiLocked(id){
    const el=_vspKpiEl(id);
    return !!(el && el.getAttribute("data-vsp-kpi-lock")==="1");
  }
  function _vspKpiLock(id){
    const el=_vspKpiEl(id);
    if(el) el.setAttribute("data-vsp-kpi-lock","1");
  }
  function _vspSetTextK(id, v){
    const el=_vspKpiEl(id);
    if(el && _vspKpiLocked(id) && _vspKpiHasValue(el)) return;
    setText(id, v);
  }
  function _vspSetHTMLK(id, v){
    const el=_vspKpiEl(id);
    if(el && _vspKpiLocked(id) && _vspKpiHasValue(el)) return;
    setHTML(id, v);
  }
'''

if "'use strict';" in s:
    s = s.replace("'use strict';", "'use strict';\n"+ins, 1)
else:
    s = ins + "\n" + s

# Replace direct writers -> guarded writers (both old and new places)
for k in ["kpi-overall","kpi-overall-sub","kpi-gate","kpi-gate-sub","kpi-gitleaks","kpi-gitleaks-sub","kpi-codeql","kpi-codeql-sub"]:
    s = s.replace(f'setText("{k}"', f'_vspSetTextK("{k}"')
    s = s.replace(f"setText('{k}'", f"_vspSetTextK('{k}'")
    s = s.replace(f'setHTML("{k}"', f'_vspSetHTMLK("{k}"')
    s = s.replace(f"setHTML('{k}'", f"_vspSetHTMLK('{k}'")

# After extras apply (the early setText of verdict), lock KPI so later status_v2 won't overwrite
# Match the known block:
#   setText("kpi-overall", verdict);
#   setText("kpi-overall-sub", `total ...`);
pat = re.compile(r'(_vspSetTextK\("kpi-overall",\s*verdict\);\s*\n\s*_vspSetTextK\("kpi-overall-sub",[^\n]*\);\s*)', re.M)
m = pat.search(s)
if m and "VSP_KPI_LOCK_AFTER_EXTRAS_P1" not in s[m.start():m.end()]:
    lock = r'''
    // --- VSP_KPI_LOCK_AFTER_EXTRAS_P1 ---
    _vspKpiLock("kpi-overall");
    _vspKpiLock("kpi-overall-sub");
    _vspKpiLock("kpi-gate");
    _vspKpiLock("kpi-gate-sub");
    _vspKpiLock("kpi-gitleaks");
    _vspKpiLock("kpi-gitleaks-sub");
    _vspKpiLock("kpi-codeql");
    _vspKpiLock("kpi-codeql-sub");
'''
    s = s[:m.end()] + lock + s[m.end():]

p.write_text(s, encoding="utf-8")
print("[OK] patched", marker)
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] restart gunicorn + hard refresh Ctrl+Shift+R"
