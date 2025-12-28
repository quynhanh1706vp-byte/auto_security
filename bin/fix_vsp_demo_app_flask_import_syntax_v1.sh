#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] not found: $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$F" "$F.bak_fix_flask_import_${TS}"
echo "[BACKUP] $F.bak_fix_flask_import_${TS}"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="replace").replace("\r\n","\n").replace("\r","\n")

def uniq(seq):
    out=[]
    seen=set()
    for x in seq:
        if x and x not in seen:
            seen.add(x); out.append(x)
    return out

# 1) Fix any ",," quickly (global safe)
while ",," in txt:
    txt = txt.replace(",,", ",")

# 2) Normalize multiline: from flask import ( ... )
m = re.search(r'(?s)\bfrom\s+flask\s+import\s*\((.*?)\)\s*', txt)
if m:
    body = m.group(1)
    # split by comma/newline, strip, remove empties
    toks = [t.strip() for t in re.split(r'[,\n]+', body) if t.strip()]
    toks = [re.sub(r'\s+', ' ', t) for t in toks]
    toks = uniq(toks)

    # ensure must-have ones for our project (won't hurt if unused)
    for must in ["Flask", "Blueprint", "request", "jsonify"]:
        if must not in toks:
            toks.append(must)

    # rebuild pretty
    rebuilt = "from flask import (\n  " + ",\n  ".join(toks) + ",\n)\n"
    txt = txt[:m.start()] + rebuilt + txt[m.end():]
else:
    # 3) Normalize single-line: from flask import a, b, c
    m2 = re.search(r'(?m)^\s*from\s+flask\s+import\s+(.+)$', txt)
    if m2:
        line = m2.group(1)
        toks = [t.strip() for t in line.split(",") if t.strip()]
        toks = uniq(toks)
        for must in ["Blueprint", "request", "jsonify"]:
            if must not in toks:
                toks.append(must)
        rebuilt = "from flask import " + ", ".join(toks) + "\n"
        txt = txt[:m2.start()] + rebuilt + txt[m2.end():]

p.write_text(txt, encoding="utf-8")
print("[OK] Rebuilt flask import clean")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] vsp_demo_app.py syntax OK"

echo "=== Preview import block ==="
python3 - << 'PY'
from pathlib import Path
import re
t = Path("vsp_demo_app.py").read_text(encoding="utf-8", errors="replace")
m = re.search(r'(?s)from flask import\s*\(.*?\)\s*\n\)', t)
if m:
    print(m.group(0))
else:
    for line in t.splitlines():
        if line.strip().startswith("from flask import"):
            print(line); break
PY
