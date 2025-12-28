#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_flask_import_${TS}"
echo "[BACKUP] $F.bak_fix_flask_import_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")
lines = s.splitlines(True)

# 1) Remove ALL existing "from flask import ..." lines (they may be malformed / in wrong place)
new_lines = []
removed = 0
for ln in lines:
    if re.match(r"^\s*from\s+flask\s+import\s+", ln):
        removed += 1
        continue
    new_lines.append(ln)

# 2) Find position BEFORE first "app = Flask(" block (multi-line ok: we just insert before first matching line)
ins = None
for i, ln in enumerate(new_lines):
    if re.match(r"^\s*app\s*=\s*Flask\s*\(", ln):
        ins = i
        break

# If no app=Flask found, still insert near top after shebang/comments
if ins is None:
    ins = 0
    for i, ln in enumerate(new_lines[:60]):
        if ln.startswith("#!") or ln.lstrip().startswith("#") or ln.strip()=="":
            ins = i+1
            continue
        break

# 3) Insert clean import (NO comments)
clean = "from flask import Flask, Response, send_file, jsonify, request\n"
new_lines.insert(ins, clean)

p.write_text("".join(new_lines), encoding="utf-8")
print(f"[OK] removed flask import lines: {removed}")
print(f"[OK] inserted clean flask import at line index: {ins}")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[NEXT] try import gateway:"
echo "  python3 -c 'import wsgi_vsp_ui_gateway; print(\"wsgi ok\")'"
