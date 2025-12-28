#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="vsp_demo_app.py"
MARK="VSP_FORCE_DEFINE_BLUEPRINT_TOP_P0_V2"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_${MARK}_${TS}"
echo "[BACKUP] $F.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

MARK = "VSP_FORCE_DEFINE_BLUEPRINT_TOP_P0_V2"
p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# If we already forced it, no-op
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

lines = s.splitlines(True)

# Insert after shebang/comments/encoding AND after initial imports block (but still very early)
ins = 0
for i, ln in enumerate(lines[:160]):
    # keep shebang + comments at top
    if ln.startswith("#!") or ln.lstrip().startswith("#") or ln.strip()=="":
        ins = i+1
        continue
    # keep early imports above guard if they exist
    if re.match(r"^\s*(from|import)\s+", ln):
        ins = i+1
        continue
    break

guard = (
    f"# {MARK}\n"
    "_VSP_Blueprint = None  # FORCE early default to avoid import-time NameError\n"
    "\n"
)

lines.insert(ins, guard)
p.write_text("".join(lines), encoding="utf-8")
print("[OK] forced _VSP_Blueprint at top index:", ins)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[NEXT] restart 8910 and verify import:"
echo "  python3 -c 'import wsgi_vsp_ui_gateway; print(\"wsgi ok\")'"
