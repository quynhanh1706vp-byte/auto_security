#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_datasource_tab_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_preferpath_${TS}"
echo "[BACKUP] $F.bak_preferpath_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_datasource_tab_v1.js")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "// === VSP_P2_DATASOURCE_TABLE_V1 ==="
if TAG not in t:
    print("[ERR] missing P2 datasource block tag"); raise SystemExit(2)

# Replace fetchFindings() to prefer PATH when rid available
pat = r"async function fetchFindings\(filters\)\{[\s\S]*?\n\s*\}"
new = r"""async function fetchFindings(filters){
    const f = Object.assign({}, (filters||{}));

    // auto-resolve latest rid if missing
    if (!f.rid && !f.run_id){
      const rid0 = (typeof resolveLatestRid === "function") ? await resolveLatestRid() : null;
      if (rid0) f.rid = rid0;
    }

    // prefer PATH endpoint to hit correct WSGI lane
    const rid = (f.rid || f.run_id || "").toString().trim();
    if (rid){
      delete f.rid;
      delete f.run_id;
      const q = buildQuery(f || {});
      const url = "/api/vsp/findings_preview_v1/" + encodeURIComponent(rid) + (q ? ("?"+q) : "");
      const r = await fetch(url, {cache:"no-store"});
      return await r.json();
    }

    // fallback (no rid)
    const q = buildQuery(f || {});
    const url = "/api/vsp/findings_preview_v1" + (q ? ("?"+q) : "");
    const r = await fetch(url, {cache:"no-store"});
    return await r.json();
  }"""

# Only patch the FIRST fetchFindings after the P2 tag
idx = t.find(TAG)
head, tail = t[:idx], t[idx:]
tail2, n = re.subn(pat, new, tail, count=1)
if n != 1:
    print("[ERR] could not patch fetchFindings() (pattern mismatch)"); raise SystemExit(2)

p.write_text(head + tail2, encoding="utf-8")
print("[OK] patched fetchFindings(): prefer PATH /findings_preview_v1/<rid>")
PY

node --check static/js/vsp_datasource_tab_v1.js
echo "[OK] node --check OK"
echo "[DONE] Prefer-PATH patch applied. Hard refresh Ctrl+Shift+R then test:"
echo "  http://127.0.0.1:8910/vsp4#tab=datasource&limit=200"
echo "  http://127.0.0.1:8910/vsp4#tab=datasource&sev=HIGH&limit=200"
