#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="./vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_force_flask_before_app_${TS}"
echo "[BACKUP] $F.bak_force_flask_before_app_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "VSP_FORCE_FLASK_SYMBOL_V1"
if TAG in t:
    print("[OK] already patched")
else:
    m = re.search(r'(?m)^(?P<indent>\s*)app\s*=\s*Flask\s*\(', t)
    if not m:
        raise SystemExit("[ERR] cannot find 'app = Flask(' line")

    ins = f'{m.group("indent")}from flask import Flask  # {TAG}\n'
    t = t[:m.start()] + ins + t[m.start():]
    p.write_text(t, encoding="utf-8")
    print("[OK] inserted Flask import right before app assignment")

PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[DONE] patch applied"
