#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$F" "$F.bak_bp_guard_${TS}"
echo "[BACKUP] $F.bak_bp_guard_${TS}"

python3 - << 'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# Find register_blueprint line for run api
pat = re.compile(r"(?m)^(?P<indent>\s*)app\.register_blueprint\(\s*(?P<bp>[A-Za-z_][A-Za-z0-9_]*)\s*\)\s*$")

lines = txt.splitlines(True)
out = []
changed = False

for line in lines:
    m = pat.match(line)
    if m and ("bp_vsp_run_api_v1" in line or "bp_vsp_run_api" in line):
        indent = m.group("indent")
        bp = m.group("bp")
        guard = (
            f"{indent}# commercial: avoid double blueprint registration\n"
            f"{indent}if getattr(app, 'blueprints', None) and '{bp}' in app.blueprints:\n"
            f"{indent}    print('[VSP_RUN_API] SKIP register blueprint (already registered): {bp}')\n"
            f"{indent}else:\n"
            f"{indent}    app.register_blueprint({bp})\n"
        )
        out.append(guard)
        changed = True
    else:
        out.append(line)

if not changed:
    print("[WARN] no matching app.register_blueprint(bp_vsp_run_api_v1/ bp_vsp_run_api) line found. No change.")
else:
    p.write_text("".join(out), encoding="utf-8")
    print("[OK] patched:", p)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
