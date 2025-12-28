#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="./vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_min_imports_${TS}"
echo "[BACKUP] $F.bak_min_imports_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "VSP_MIN_IMPORTS_COMMERCIAL_V1"
if TAG in t:
    print("[OK] already has", TAG)
else:
    block = f'''
# === {TAG} ===
# Hardened minimal imports to avoid NameError chain after patches
import os, sys, json, time, re, subprocess
from pathlib import Path
try:
    from flask import Flask, Blueprint, request, jsonify, Response, abort, send_file
except Exception:
    # allow import-time failure to surface clearly
    Flask = Blueprint = request = jsonify = Response = abort = send_file = None
# === END {TAG} ===

'''
    # insert after shebang/encoding and after first docstring if exists; else near top
    # keep it very early so symbols exist before usage
    # place after initial comments and empty lines
    m = re.search(r"(?ms)\A(\s*(?:#.*\n)*\s*)", t)
    pos = m.end(1) if m else 0
    t = t[:pos] + block + t[pos:]
    p.write_text(t, encoding="utf-8")
    print("[OK] inserted", TAG)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[DONE] imports hardened"
