#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="vsp_demo_app.py"
MARK="VSP_FORCE_BLUEPRINT_IMPORT_P0_V1"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_${MARK}_${TS}"
echo "[BACKUP] $F.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

# Try to extend an existing flask import line
m = re.search(r"^from\s+flask\s+import\s+([^\n]+)$", s, flags=re.M)
if m:
    items = [x.strip() for x in m.group(1).split(",")]
    if "Blueprint" not in items:
        items.append("Blueprint")
        new_line = "from flask import " + ", ".join(items)
        s = s[:m.start()] + new_line + s[m.end():]
        print("[OK] extended flask import with Blueprint")
    else:
        print("[OK] Blueprint already in flask import")
else:
    # insert near top
    lines=s.splitlines(True)
    ins=0
    for i,ln in enumerate(lines[:80]):
        if ln.startswith("#!") or ln.lstrip().startswith("#") or ln.strip()=="":
            ins=i+1; continue
        if re.match(r"^\s*(from|import)\s+", ln):
            ins=i+1; continue
        break
    lines.insert(ins, "from flask import Blueprint\n")
    s="".join(lines)
    print("[OK] inserted 'from flask import Blueprint' at top")

p.write_text(s, encoding="utf-8")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[NEXT] restart 8910 then verify import:"
echo "  python3 -c 'import wsgi_vsp_ui_gateway; print(\"wsgi ok\")'"
