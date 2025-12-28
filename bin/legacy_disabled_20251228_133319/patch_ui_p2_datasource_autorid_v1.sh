#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_datasource_tab_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_autorid_${TS}"
echo "[BACKUP] $F.bak_autorid_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_datasource_tab_v1.js")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "// === VSP_P2_DATASOURCE_TABLE_V1 ==="
if TAG not in t:
    print("[ERR] missing P2 datasource block tag"); raise SystemExit(2)

if "// === VSP_P2_AUTORID_V1 ===" in t:
    print("[OK] autorid already present, skip"); raise SystemExit(0)

# inject helper near fetchFindings()
needle = "async function fetchFindings(filters){"
pos = t.find(needle)
if pos < 0:
    print("[ERR] fetchFindings() not found"); raise SystemExit(2)

inject = r'''
  // === VSP_P2_AUTORID_V1 ===
  let _vspLatestRidCache = null;
  async function resolveLatestRid(){
    if (_vspLatestRidCache) return _vspLatestRidCache;
    try{
      const r = await fetch("/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1", {cache:"no-store"});
      const j = await r.json();
      const rid = j?.items?.[0]?.run_id || j?.items?.[0]?.rid || j?.items?.[0]?.id || null;
      if (rid) _vspLatestRidCache = rid;
      return rid;
    }catch(e){
      return null;
    }
  }
'''

t = t[:pos] + inject + "\n" + t[pos:]

# patch fetchFindings to auto add rid if missing
t2 = re.sub(
    r"async function fetchFindings\(filters\)\{\s*const q = buildQuery\(filters \|\| \{\}\);\s*const url = \"/api/vsp/findings_preview_v1\" \+ \(q \? \(\"\?\" \+ q\) : \"\"\);\s*const r = await fetch\(url, \{cache:\"no-store\"\}\);\s*const j = await r\.json\(\);\s*return j;\s*\}",
    r"""async function fetchFindings(filters){
    const f = Object.assign({}, (filters||{}));
    // if backend requires RID, auto-resolve latest
    if (!f.rid && !f.run_id){
      const rid = await resolveLatestRid();
      if (rid) f.rid = rid;
    }
    const q = buildQuery(f || {});
    const url = "/api/vsp/findings_preview_v1" + (q ? ("?"+q) : "");
    const r = await fetch(url, {cache:"no-store"});
    const j = await r.json();
    return j;
  }""",
    t,
    count=1
)

p.write_text(t2, encoding="utf-8")
print("[OK] injected autorid + patched fetchFindings()")
PY

node --check static/js/vsp_datasource_tab_v1.js
echo "[OK] node --check OK"
echo "[DONE] autorid patch applied. Hard refresh Ctrl+Shift+R then test:"
echo "  http://127.0.0.1:8910/vsp4#tab=datasource&limit=200"
