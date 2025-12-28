#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="./vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_force_path_before_root_${TS}"
echo "[BACKUP] $F.bak_force_path_before_root_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "VSP_FORCE_PATH_SYMBOL_V3"
if TAG in t:
    print("[OK] already patched")
else:
    # Find the exact ROOT assignment that uses Path(...)
    m = re.search(r'(?m)^(?P<indent>\s*)ROOT\s*=\s*Path\s*\(', t)
    if not m:
        raise SystemExit("[ERR] cannot find 'ROOT = Path(' line to patch")

    ins = f'{m.group("indent")}from pathlib import Path  # {TAG}\n'
    # Insert import immediately before the ROOT line
    t = t[:m.start()] + ins + t[m.start():]
    p.write_text(t, encoding="utf-8")
    print("[OK] inserted Path import right before ROOT assignment")

PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[DONE] patch applied"
