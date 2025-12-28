#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_outci_${TS}"
echo "[BACKUP] $F.bak_fix_outci_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("vsp_demo_app.py")
t=p.read_text(encoding="utf-8", errors="ignore")
t2=t.replace("ui/out_ci", "out_ci")
if t2==t:
    print("[WARN] no 'ui/out_ci' occurrences found (maybe already clean)")
else:
    print("[OK] replaced 'ui/out_ci' -> 'out_ci'")
p.write_text(t2, encoding="utf-8")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
