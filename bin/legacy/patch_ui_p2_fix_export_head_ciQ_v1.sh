#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_ciQ_${TS}"
echo "[BACKUP] $F.bak_fix_ciQ_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_ui_4tabs_commercial_v1.js")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "// === VSP_P2_FIX_EXPORT_CIQ_V1 ==="
if TAG in t:
    print("[OK] already patched"); raise SystemExit(0)

# Only patch the run_export_v3 candidate URLs (safe + minimal)
rep = r"${(__ciQ||\"\").replace(/^\\?/, \"&\")}"

patterns = [
  (r"\$\{__ciQ\}", rep),
]

# But apply replacement ONLY within lines that contain "/api/vsp/run_export_v3"
lines = t.splitlines(True)
out = []
changed = 0
for ln in lines:
    if "/api/vsp/run_export_v3" in ln and "${__ciQ}" in ln:
        ln2 = ln.replace("${__ciQ}", rep)
        if ln2 != ln:
            changed += 1
        out.append(ln2)
    else:
        out.append(ln)

t2 = "".join(out)
t2 = t2.rstrip() + "\n\n" + TAG + "\n// patched run_export_v3 candidate URLs to normalize __ciQ leading '?'\n"

p.write_text(t2, encoding="utf-8")
print(f"[OK] patched lines={changed} (expected >=1)")
PY

node --check static/js/vsp_ui_4tabs_commercial_v1.js >/dev/null
echo "[OK] node --check OK"
echo "[DONE] export HEAD ciQ fix applied. Hard refresh Ctrl+Shift+R."
