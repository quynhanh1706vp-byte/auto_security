#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_repair_colon_${TS}"
echo "[BACKUP] $F.bak_repair_colon_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# Fix: def _vsp_demoapp_apply_wrappers_v3(app)  -> add colon if missing
pat = re.compile(r"^(\s*def\s+_vsp_demoapp_apply_wrappers_v3\s*\(\s*app\s*\))\s*$", re.M)
txt2, n = pat.subn(r"\1:", txt)

if n == 0:
    print("[INFO] no missing-colon def line found (maybe already fixed).")
else:
    print(f"[OK] fixed missing colon on def _vsp_demoapp_apply_wrappers_v3(app): count={n}")

p.write_text(txt2, encoding="utf-8")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
