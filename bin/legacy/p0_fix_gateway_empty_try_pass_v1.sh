#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fixtry_${TS}"
echo "[BACKUP] ${F}.bak_fixtry_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

try_re = re.compile(r'^(\s*)try:\s*(#.*)?$')
ctrl_re = re.compile(r'^(\s*)(except\b|finally\b|else\b)\b')

patched = 0
out = []
n = len(lines)

for i, line in enumerate(lines):
    out.append(line)
    m = try_re.match(line)
    if not m:
        continue

    base_indent = m.group(1)
    # find next significant (non-empty, non-comment-only) line
    j = i + 1
    while j < n:
        nxt = lines[j]
        if nxt.strip() == "":
            j += 1
            continue
        # comment-only line at same indent doesn't count as body
        if re.match(r'^\s*#', nxt):
            j += 1
            continue
        break

    if j >= n:
        # try: at EOF -> add pass
        out.append(base_indent + "    pass\n")
        patched += 1
        continue

    nxt = lines[j]
    m2 = ctrl_re.match(nxt)
    # If next is except/finally/else at same indent => empty try body
    if m2 and m2.group(1) == base_indent:
        out.append(base_indent + "    pass\n")
        patched += 1

p.write_text("".join(out), encoding="utf-8")
print(f"[OK] inserted pass for empty try blocks: {patched}")
PY

echo "== py_compile =="
python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"
