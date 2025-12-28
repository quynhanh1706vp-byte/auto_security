#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_prestart_guard_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")
lines=s.splitlines(True)
out=[]
rm=0
for ln in lines:
    if re.match(r'^\s*\\n\s*$', ln):
        rm += 1
        continue
    out.append(ln)
if rm:
    p.write_text("".join(out), encoding="utf-8")
print("[OK] removed_literal_backslash_n_lines=", rm)
PY

python3 -m py_compile "$APP" && echo "[OK] py_compile OK"
