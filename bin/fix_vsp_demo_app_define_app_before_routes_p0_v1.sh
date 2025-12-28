#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_app_before_routes_${TS}"
echo "[BACKUP] $F.bak_fix_app_before_routes_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

lines=s.splitlines(True)

def find_first_app_decorator(ls):
    for i,ln in enumerate(ls):
        if ln.lstrip().startswith("@app."):
            return i
    return None

def find_app_flask_block(ls):
    # find "app = Flask(" and capture until parens balanced (multi-line)
    for i,ln in enumerate(ls):
        if re.match(r"^\s*app\s*=\s*Flask\s*\(", ln):
            # capture block
            block=[ln]
            bal = ln.count("(") - ln.count(")")
            j=i+1
            while j < len(ls) and bal > 0:
                block.append(ls[j])
                bal += ls[j].count("(") - ls[j].count(")")
                j += 1
            return i, j, "".join(block)
    return None

i_dec = find_first_app_decorator(lines)
if i_dec is None:
    print("[OK] no @app.* decorator found; nothing to reorder.")
    p.write_text("".join(lines), encoding="utf-8")
    raise SystemExit(0)

blk = find_app_flask_block(lines)

if blk:
    i0,i1,block = blk
    if i0 < i_dec:
        print("[OK] app = Flask(...) already before first decorator.")
        p.write_text("".join(lines), encoding="utf-8")
        raise SystemExit(0)

    # remove block from below
    new = lines[:i0] + lines[i1:]
    # recompute decorator position in new
    i_dec2 = find_first_app_decorator(new)
    assert i_dec2 is not None

    # insert block right before first decorator
    new = new[:i_dec2] + [block if block.endswith("\n") else block+"\n"] + ["\n"] + new[i_dec2:]
    p.write_text("".join(new), encoding="utf-8")
    print("[OK] moved app = Flask(...) block above first @app.* decorator.")
else:
    # No app = Flask(...) found anywhere -> inject minimal app before first decorator
    text = "".join(lines)

    # ensure Flask import exists somewhere (best-effort)
    if not re.search(r"\bfrom\s+flask\s+import\b.*\bFlask\b", text) and not re.search(r"\bimport\s+flask\b", text):
        # insert a safe import near top (after shebang/encoding/comments)
        insert_at = 0
        for i,ln in enumerate(lines[:40]):
            if ln.startswith("#!") or ln.lstrip().startswith("#") or ln.strip()=="":
                insert_at = i+1
                continue
            break
        lines.insert(insert_at, "from flask import Flask\n")
        i_dec = find_first_app_decorator(lines)

    # inject app definition
    inject = "app = Flask(__name__)\n\n"
    lines = lines[:i_dec] + [inject] + lines[i_dec:]
    p.write_text("".join(lines), encoding="utf-8")
    print("[OK] injected app = Flask(__name__) above first @app.* decorator (no app=Flask found).")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[NEXT] start 8910 again then verify import:"
echo "  python3 -c 'import wsgi_vsp_ui_gateway; print(\"wsgi ok\")'"
