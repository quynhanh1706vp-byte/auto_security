#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_import_flask_${TS}"
echo "[BACKUP] $F.bak_fix_import_flask_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

# If a flask import exists, ensure it includes Flask (+ common helpers)
m = re.search(r"^from\s+flask\s+import\s+([^\n]+)$", s, flags=re.M)
want = ["Flask","Response","send_file","jsonify","request"]
if m:
    items = [x.strip() for x in m.group(1).split(",")]
    changed = False
    for w in want:
        if w not in items:
            items.append(w); changed=True
    if changed:
        new_line = "from flask import " + ", ".join(items)
        s = s[:m.start()] + new_line + s[m.end():]
        print("[OK] extended existing flask import:", new_line)
    else:
        print("[OK] flask import already has needed symbols")
else:
    # Insert near top (after shebang/comments/encoding)
    lines=s.splitlines(True)
    insert_at=0
    for i,ln in enumerate(lines[:40]):
        if ln.startswith("#!") or ln.lstrip().startswith("#") or ln.strip()=="":
            insert_at=i+1
            continue
        break
    lines.insert(insert_at, "from flask import Flask, Response, send_file, jsonify, request\n")
    s="".join(lines)
    print("[OK] inserted flask import at top")

p.write_text(s, encoding="utf-8")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[NEXT] start 8910 again:"
echo "  python3 -c 'import wsgi_vsp_ui_gateway; print(\"wsgi ok\")'"
