#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# Find bundle which contains our marker
BUNDLE="$(python3 - <<'PY'
from pathlib import Path
root = Path("static/js")
cands=[]
for p in root.glob("*.js"):
    try:
        s=p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if "VSP_P1_RULE_OVERRIDES_AUTOREFRESH_V1" in s:
        cands.append(p)
cands=sorted(cands, key=lambda x:x.name)
print(str(cands[0]) if cands else "")
PY
)"
[ -n "$BUNDLE" ] || { echo "[ERR] cannot find bundle containing VSP_P1_RULE_OVERRIDES_AUTOREFRESH_V1"; exit 2; }

cp -f "$BUNDLE" "${BUNDLE}.bak_fix_true_${TS}"
echo "[BACKUP] ${BUNDLE}.bak_fix_true_${TS}"

python3 - <<'PY'
from pathlib import Path
import os, re

bundle = Path(os.environ["BUNDLE"])
s = bundle.read_text(encoding="utf-8", errors="replace")

# Replace the invalid JS token True safely
before = s
s = s.replace("j.ok === True || ", "")  # remove only that part
s = s.replace("j.ok === True", "j.ok === true")  # fallback if format differs

if s == before:
    print("[WARN] no 'True' token found to patch (maybe already fixed).")
else:
    bundle.write_text(s, encoding="utf-8")
    print("[OK] patched True->true in:", bundle)
PY
BUNDLE="$BUNDLE"

echo "[OK] done. restart UI + hard refresh after backend patch too."
