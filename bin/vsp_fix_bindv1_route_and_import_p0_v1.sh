#!/usr/bin/env bash
set -euo pipefail
PROJ="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$PROJ"

PY="python3"
[ -x ".venv/bin/python" ] && PY=".venv/bin/python"
echo "[PY]=$PY"
echo "[CWD]=$PWD"

# (1) Patch BindV1.route forwarder (if missing)
"$PY" - <<'PY'
import re, sys
from pathlib import Path

root = Path(".").resolve()
cands = []
for p in root.rglob("*.py"):
    try:
        s = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if "class BindV1" in s:
        cands.append(p)

if not cands:
    print("[ERR] cannot find 'class BindV1' anywhere under", root)
    sys.exit(2)

# pick the most likely: shortest path / or inside ui gateway modules
cands.sort(key=lambda x: (len(str(x)), str(x)))
p = cands[0]
s = p.read_text(encoding="utf-8", errors="replace")

if re.search(r"\n\s*def\s+route\s*\(", s):
    print("[OK] BindV1 already has route():", p)
    sys.exit(0)

m = re.search(r"(^class\s+BindV1\b[^\n]*\n)", s, flags=re.M)
if not m:
    print("[ERR] cannot anchor class BindV1 header in:", p)
    sys.exit(3)

# Find indent for methods inside class (assume 4 spaces if unknown)
# We'll inject right after class header line.
hdr_end = m.end(1)
# detect class body indent by looking at next non-empty line
after = s[hdr_end:]
lines = after.splitlines(True)
indent = "    "
for ln in lines[:40]:
    if ln.strip() == "":
        continue
    mi = re.match(r"^(\s+)\S", ln)
    if mi:
        indent = mi.group(1)
    break

MARK = "VSP_BINDV1_ROUTE_FORWARD_P0_V1"
inject = (
    f"{indent}# {MARK}\n"
    f"{indent}def route(self, rule, **options):\n"
    f"{indent}    \"\"\"Flask-compatible decorator forwarder.\"\"\"\n"
    f"{indent}    target = None\n"
    f"{indent}    for k in ('bp','blueprint','_bp','app','_app'):\n"
    f"{indent}        if hasattr(self, k):\n"
    f"{indent}            target = getattr(self, k)\n"
    f"{indent}            break\n"
    f"{indent}    if target is None:\n"
    f"{indent}        raise AttributeError('BindV1 has no bp/app to route')\n"
    f"{indent}    return target.route(rule, **options)\n\n"
)

out = s[:hdr_end] + inject + s[hdr_end:]
bak = p.with_suffix(p.suffix + ".bak_bindv1_route")
bak.write_text(s, encoding="utf-8")
p.write_text(out, encoding="utf-8")

print("[BACKUP]", bak)
print("[OK] injected BindV1.route into", p)

# compile quick
import py_compile
py_compile.compile(str(p), doraise=True)
print("[OK] py_compile:", p)
PY

# (2) Verify wsgi import (common failure if chạy sai cwd/PYTHONPATH)
export PYTHONPATH="$PROJ:${PYTHONPATH:-}"
"$PY" - <<'PY'
import sys, os
print("[INFO] sys.path[0]=", sys.path[0])
print("[INFO] cwd=", os.getcwd())

try:
    import wsgi_vsp_ui_gateway as m
    print("[OK] import wsgi_vsp_ui_gateway")
    app = getattr(m, "application", None)
    print("[OK] application=", bool(app))
except Exception as e:
    print("[ERR] import failed:", repr(e))
    raise
PY

echo "[DONE] BindV1.route fixed + import OK"
