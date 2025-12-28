#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="vsp_demo_app.py"
MARK="VSP_NULL_BLUEPRINTS_P0_V1"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_${MARK}_${TS}"
echo "[BACKUP] $F.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

MARK="VSP_NULL_BLUEPRINTS_P0_V1"
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Find earliest decorator usage of *_bp.get/post/route
bp_names = set(re.findall(r"^\s*@([A-Za-z_]\w*_bp)\.(get|post|put|delete|route)\b", s, flags=re.M))
bp_list = sorted({name for name,_ in bp_names})
# Ensure at least the one we saw
if "vsp_runs_fs_bp" not in bp_list:
    bp_list.insert(0, "vsp_runs_fs_bp")

# If any of these are already defined before their first usage, still safe to re-define only if missing:
# We'll create guards: if 'name' not in globals(): name = NullBlueprint()
defs = "\n".join([f"if '{n}' not in globals():\n    {n} = _VSP_NullBlueprint('{n}')" for n in bp_list])

inject = f"""
# {MARK}
class _VSP_NullBlueprint:
    \"\"\"Degrade-graceful Blueprint shim: decorators become no-ops so app can boot.\"\"\"
    def __init__(self, name): self.name=name
    def route(self, *a, **k):
        def dec(fn): return fn
        return dec
    def get(self, *a, **k): return self.route(*a, **k)
    def post(self, *a, **k): return self.route(*a, **k)
    def put(self, *a, **k): return self.route(*a, **k)
    def delete(self, *a, **k): return self.route(*a, **k)

{defs}

# /{MARK}
""".strip("\n")

# Insert very early: after initial imports block
lines=s.splitlines(True)
ins=0
for i,ln in enumerate(lines[:220]):
    if ln.startswith("#!") or ln.lstrip().startswith("#") or ln.strip()=="":
        ins=i+1; continue
    if re.match(r"^\s*(from|import)\s+", ln):
        ins=i+1; continue
    break

lines.insert(ins, inject + "\n\n")
p.write_text("".join(lines), encoding="utf-8")

print("[OK] injected NullBlueprint shim + guarded defs for:", ", ".join(bp_list[:8]) + (" ..." if len(bp_list)>8 else ""))
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[NEXT] restart 8910 then check:"
echo "  python3 -c 'import wsgi_vsp_ui_gateway; print(\"wsgi ok\")'"
