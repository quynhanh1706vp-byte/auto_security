#!/usr/bin/env bash
set -euo pipefail
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }

cp -f "$APP" "$APP.bak_rm_hook_$(date +%Y%m%d_%H%M%S)"

python3 - <<'PY'
import re
from pathlib import Path
p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

out=[]
skip=False
for ln in lines:
    if "BEGIN VSP_WATCHDOG_HOOK_V1" in ln:
        skip=True
        continue
    if skip:
        if "END VSP_WATCHDOG_HOOK_V1" in ln:
            skip=False
        continue
    # fallback: remove stray lines from older injections
    if "run_api.vsp_watchdog_hook_v1" in ln or "VSP_WD_HOOK" in ln:
        continue
    out.append(ln)

p.write_text("".join(out), encoding="utf-8")
print("[OK] hook removed")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK (hook removed)"
