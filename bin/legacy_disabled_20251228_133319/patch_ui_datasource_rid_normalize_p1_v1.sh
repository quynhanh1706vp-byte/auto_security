#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_datasource_tab_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_rid_norm_${TS}" && echo "[BACKUP] $F.bak_rid_norm_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_datasource_tab_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

if "function normalizeRid" not in s:
    # inject helper near top (after first IIFE/use strict if present)
    ins = r'''
  function normalizeRid(x){
    x = String(x||"").trim();
    // common: RUN_<RID>
    x = x.replace(/^RUN[_\s]+/i, "");
    // try extract canonical VSP_CI_YYYYmmdd_HHMMSS
    const m = x.match(/(VSP_CI_\d{8}_\d{6})/i);
    if (m) return m[1];
    // fallback: collapse spaces -> underscores
    x = x.replace(/\s+/g, "_");
    return x;
  }

'''
    # place after 'use strict'; if exists else at top
    if "'use strict';" in s:
        s = s.replace("'use strict';", "'use strict';\n"+ins, 1)
    else:
        s = ins + s

# wherever rid is derived, ensure normalizeRid
# common patterns: const rid = getRidFromState() / window.VSP_RID_STATE...
s = re.sub(r'const\s+rid\s*=\s*([^;]+);',
           lambda m: f"const rid = normalizeRid({m.group(1)});",
           s, count=1)

# also normalize if they later reassign rid
s = re.sub(r'rid\s*=\s*([^;]+);',
           lambda m: f"rid = normalizeRid({m.group(1)});",
           s)

p.write_text(s, encoding="utf-8")
print("[OK] injected normalizeRid + applied to rid usage")
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] Hard refresh Ctrl+Shift+R"
