#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_extras_reader_${TS}" && echo "[BACKUP] $F.bak_extras_reader_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_ui_4tabs_commercial_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_EXTRAS_READER_USE_KPI_ROOT_P1_V1"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

# We patch the apply/tryApply function area by replacing the lines:
#   const k = j.kpi || {};
#   const byTool = k.by_tool || j.by_tool || {};
#   const bySev  = k.by_sev  || j.by_sev  || {};
# with a robust version that also checks nested
pat = re.compile(
    r'const\s+k\s*=\s*j\.kpi\s*\|\|\s*\{\}\s*;\s*\n\s*const\s+byTool\s*=\s*k\.by_tool\s*\|\|\s*j\.by_tool\s*\|\|\s*\{\}\s*;\s*\n\s*const\s+bySev\s*=\s*k\.by_sev\s*\|\|\s*j\.by_sev\s*\|\|\s*\{\}\s*;',
    re.M
)

repl = r'''// === VSP_EXTRAS_READER_USE_KPI_ROOT_P1_V1 ===
    const k = (j && j.kpi) ? j.kpi : {};
    // prefer kpi.* (our API returns only {ok,rid,sources,kpi})
    const byTool = (k && (k.by_tool || k.byTool)) || (j && (j.by_tool || j.byTool)) || {};
    const bySev  = (k && (k.by_sev  || k.bySev))  || (j && (j.by_sev  || j.bySev))  || {};
    const topCwe = (k && (k.top_cwe || k.topCwe)) || (j && (j.top_cwe || j.topCwe)) || [];
'''

if not pat.search(s):
    # if the exact 3-line block not found, do a softer injection:
    # Insert a helper just before "function tryApply(" if exists.
    m = re.search(r'function\s+tryApply\s*\(\s*j\s*\)\s*\{', s)
    if not m:
        raise SystemExit("[ERR] cannot find tryApply(j){ to patch")
    # inject helper right after function start
    insert = r'''
  // === VSP_EXTRAS_READER_USE_KPI_ROOT_P1_V1 ===
  function _vspPick(obj, keys){
    try{
      for(const k of keys){
        if(obj && obj[k] !== undefined) return obj[k];
      }
    }catch(_){}
    return undefined;
  }
'''
    s = s[:m.end()] + insert + s[m.end():]
    # now patch inside tryApply by adding robust extraction right after `if(!j || !j.kpi) return false;` or `if(!j) return false;`
    s = re.sub(
        r'(if\s*\(\s*!\s*j\s*\)\s*return\s*false;\s*)',
        r'\1\n    const k = (j && j.kpi) ? j.kpi : {};\n    const byTool = _vspPick(k, ["by_tool","byTool"]) || _vspPick(j, ["by_tool","byTool"]) || {};\n    const bySev  = _vspPick(k, ["by_sev","bySev"])  || _vspPick(j, ["by_sev","bySev"])  || {};\n    const topCwe = _vspPick(k, ["top_cwe","topCwe"])|| _vspPick(j, ["top_cwe","topCwe"])|| [];\n',
        s,
        count=1
    )
else:
    s = pat.sub(repl, s, count=1)

p.write_text(s, encoding="utf-8")
print("[OK] patched", marker)
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] restart gunicorn + hard refresh Ctrl+Shift+R"
