#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="./vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_force_response_before_proxy_get_${TS}"
echo "[BACKUP] $F.bak_force_response_before_proxy_get_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "VSP_FORCE_RESPONSE_SYMBOL_V1"
if TAG in t:
    print("[OK] already patched")
else:
    # find the proxy_get signature that annotates Response
    m = re.search(r'(?m)^(?P<indent>\s*)def\s+proxy_get\s*\(.*?\)\s*->\s*Response\s*:', t)
    if not m:
        # fallback: any function that returns Response
        m = re.search(r'(?m)^(?P<indent>\s*)def\s+\w+\s*\(.*?\)\s*->\s*Response\s*:', t)
    if not m:
        raise SystemExit("[ERR] cannot find function annotated with -> Response")

    ins = f'{m.group("indent")}from flask import Response  # {TAG}\n'
    t = t[:m.start()] + ins + t[m.start():]
    p.write_text(t, encoding="utf-8")
    print("[OK] inserted Response import right before function definition")

PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[DONE] patch applied"
