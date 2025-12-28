#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_datasource_tab_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_sev_redecl_${TS}" && echo "[BACKUP] $F.bak_fix_sev_redecl_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_datasource_tab_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

# Fix redeclare: const sev = counts.by_sev -> const sevCounts = ...
s2 = s.replace(
    "const sev = (j.counts||{}).by_sev||{};",
    "const sevCounts = (j.counts||{}).by_sev||{};"
)

# Update uses in the mini string builder if present
s2 = s2.replace("Object.keys(sev).sort()", "Object.keys(sevCounts).sort()")
s2 = s2.replace("${k}:${sev[k]}", "${k}:${sevCounts[k]}")

if s2 == s:
    raise SystemExit("[ERR] pattern not found; paste lines around the meta block (ds-meta)")

p.write_text(s2, encoding="utf-8")
print("[OK] fixed sev redeclare -> sevCounts")
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] Hard refresh browser (Ctrl+Shift+R)."
