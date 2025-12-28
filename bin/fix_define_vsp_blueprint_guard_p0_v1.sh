#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="vsp_demo_app.py"
MARK="VSP_BLUEPRINT_GUARD_P0_V1"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_${MARK}_${TS}"
echo "[BACKUP] $F.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# If _VSP_Blueprint is already defined anywhere, skip
if re.search(r"^\s*_VSP_Blueprint\s*=", s, flags=re.M):
    print("[OK] _VSP_Blueprint already defined; no-op")
    raise SystemExit(0)

# Insert near top (after shebang/comments/encoding and after flask imports if present)
lines = s.splitlines(True)
ins = 0
for i, ln in enumerate(lines[:80]):
    if ln.startswith("#!") or ln.lstrip().startswith("#") or ln.strip()=="":
        ins = i+1
        continue
    # keep imports together: if we're still in import section, move insertion after it
    if re.match(r"^\s*(from|import)\s+", ln):
        ins = i+1
        continue
    break

guard = f"# {MARK}\n_VSP_Blueprint = None  # default safe; optional blueprint may be injected elsewhere\n\n"
lines.insert(ins, guard)

p.write_text("".join(lines), encoding="utf-8")
print("[OK] inserted _VSP_Blueprint guard at line index:", ins)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[NEXT] verify import:"
echo "  python3 -c 'import wsgi_vsp_ui_gateway; print(\"wsgi ok\")'"
