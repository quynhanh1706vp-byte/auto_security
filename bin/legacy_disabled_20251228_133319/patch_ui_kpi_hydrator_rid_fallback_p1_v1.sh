#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_rid_fallback_${TS}" && echo "[BACKUP] $F.bak_rid_fallback_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_ui_4tabs_commercial_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_KPI_HYDRATOR_RID_FALLBACK_P1_V1"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

# 1) inject fetchLatestRid helper inside the hydrator IIFE (right after _getRid() function end)
# We'll find "function _getRid(){" and inject after its closing "return \"\"; }"
m = re.search(r'function\s+_getRid\s*\(\)\s*\{', s)
if not m:
    raise SystemExit("[ERR] cannot find _getRid() in hydrator block")

# find end of _getRid by locating the next "return \"\";" then the following "}"
end = re.search(r'return\s+"";\s*\n\s*\}', s[m.start():], re.M)
if not end:
    raise SystemExit("[ERR] cannot find end of _getRid() to inject")

inj_pos = m.start() + end.end()

helper = r'''

  // === VSP_KPI_HYDRATOR_RID_FALLBACK_P1_V1 ===
  async function _fetchLatestRid(){
    try{
      const u="/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1";
      const r=await fetch(u,{cache:"no-store"});
      if(!r.ok) return "";
      const j=await r.json();
      const it = (j && j.items && j.items[0]) ? j.items[0] : null;
      const rid = it ? (it.run_id || it.rid || "") : "";
      return _normRid(rid);
    }catch(_){ return ""; }
  }
'''

s = s[:inj_pos] + helper + s[inj_pos:]

# 2) patch _run() so it falls back to _fetchLatestRid when rid is empty
pat = re.compile(r'const\s+rid\s*=\s*_getRid\(\)\s*;\s*\n\s*if\s*\(\s*!rid\s*\)\s*return\s*;\s*', re.M)
if not pat.search(s):
    raise SystemExit("[ERR] cannot find 'const rid=_getRid(); if(!rid) return;' in _run()")
s = pat.sub('let rid=_getRid();\n      if(!rid) rid = await _fetchLatestRid();\n      if(!rid) return;\n', s, count=1)

# append marker comment near end
s += "\n// " + marker + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched", marker)
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] restart gunicorn + hard refresh Ctrl+Shift+R"
