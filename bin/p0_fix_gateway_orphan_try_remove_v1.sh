#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_rm_orphan_try_${TS}"
echo "[BACKUP] ${F}.bak_rm_orphan_try_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

try_re = re.compile(r'^(\s*)try:\s*(#.*)?$')
pass_re = re.compile(r'^(\s*)pass\s*(#.*)?$')
ctrl_re = re.compile(r'^\s*(except\b|finally\b|else\b)\b')

def indent_width(s: str) -> int:
    return len(s.replace("\t", "    "))

out = []
i = 0
removed = 0
n = len(lines)

while i < n:
    line = lines[i]
    m = try_re.match(line)
    if not m:
        out.append(line)
        i += 1
        continue

    base = m.group(1)
    base_w = indent_width(base)

    # next significant line
    j = i + 1
    while j < n and (lines[j].strip()=="" or re.match(r'^\s*#', lines[j])):
        j += 1

    if j >= n:
        out.append(line); i += 1
        continue

    # must be a pass indented deeper
    mpass = pass_re.match(lines[j])
    if not mpass:
        out.append(line); i += 1
        continue

    pass_indent = mpass.group(1)
    if indent_width(pass_indent) <= base_w:
        out.append(line); i += 1
        continue

    # find next significant after pass
    k = j + 1
    while k < n and (lines[k].strip()=="" or re.match(r'^\s*#', lines[k])):
        k += 1

    if k >= n:
        out.append(line); i += 1
        continue

    # if next significant is NOT except/finally/else at same indent => orphan try
    next_line = lines[k]
    next_prefix = re.match(r'^(\s*)', next_line).group(1)
    if indent_width(next_prefix) == base_w and not ctrl_re.match(next_line):
        # drop try line + pass line; keep everything else
        removed += 1
        i = j + 1
        continue

    # otherwise keep as-is
    out.append(line)
    i += 1

p.write_text("".join(out), encoding="utf-8")
print(f"[OK] removed orphan try blocks: {removed}")
PY

echo "== py_compile =="
python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"
