#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$F" "$F.bak_fix_flask_import_${TS}"
echo "[BACKUP] $F.bak_fix_flask_import_${TS}"

python3 - << 'PY'
from pathlib import Path

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n").splitlines(True)

def parse_names_from_block(block: str):
    # block includes "from flask import ..." possibly with parentheses/newlines
    s = block
    s = s.replace("from flask import", "", 1)
    # drop parentheses
    s = s.replace("(", " ").replace(")", " ")
    # normalize separators
    s = s.replace("\n", " ").replace("\t", " ")
    parts = [x.strip() for x in s.split(",")]
    out = []
    seen = set()
    for t in parts:
        t = t.strip()
        if not t:
            continue
        # keep only valid-ish identifiers
        t = "".join(ch for ch in t if (ch.isalnum() or ch == "_"))
        if not t:
            continue
        if t not in seen:
            out.append(t); seen.add(t)
    return out

# locate "from flask import" (single or multi-line)
i = 0
changed = False
while i < len(lines):
    if lines[i].lstrip().startswith("from flask import"):
        start = i
        block = lines[i]
        # multiline if contains "(" but not ")"
        if "(" in lines[i] and ")" not in lines[i]:
            j = i + 1
            while j < len(lines) and ")" not in lines[j]:
                block += lines[j]
                j += 1
            if j < len(lines):
                block += lines[j]
                end = j
            else:
                end = i
        else:
            end = i

        names = parse_names_from_block(block)

        # Ensure required for API JSON guard
        for need in ("jsonify", "request"):
            if need not in names:
                names.append(need)

        # Ensure minimal Flask app symbol (keep existing if present)
        if "Flask" not in names:
            names.insert(0, "Flask")

        new_line = "from flask import " + ", ".join(names) + "\n"
        lines[start:end+1] = [new_line]
        changed = True
        i = start + 1
        # keep scanning in case file has multiple "from flask import" lines
        continue
    i += 1

if not changed:
    # If no import found, prepend safe minimal import
    lines.insert(0, "from flask import Flask, jsonify, request\n")

p.write_text("".join(lines), encoding="utf-8")
print("[OK] fixed flask import block(s)")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
