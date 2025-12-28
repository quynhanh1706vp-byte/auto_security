#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fixtry_v2_${TS}"
echo "[BACKUP] ${F}.bak_fixtry_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

try_re  = re.compile(r'^(\s*)try:\s*(#.*)?$')
ctrl_re = re.compile(r'^\s*(except\b|finally\b|else\b)\b')

def indent_width(prefix: str) -> int:
    # normalize tabs as 4 spaces to compare "width"
    return len(prefix.replace("\t", "    "))

patched = 0
out = []
n = len(lines)

for i, line in enumerate(lines):
    out.append(line)
    m = try_re.match(line)
    if not m:
        continue

    base_prefix = m.group(1)
    base_w = indent_width(base_prefix)

    # find next significant line (skip blank + comment-only)
    j = i + 1
    while j < n:
        nxt = lines[j]
        if nxt.strip() == "":
            j += 1
            continue
        if re.match(r'^\s*#', nxt):
            j += 1
            continue
        break

    # EOF -> empty
    if j >= n:
        out.append(base_prefix + "    pass\n")
        patched += 1
        continue

    nxt = lines[j]
    # compute next line indent width
    nxt_prefix = re.match(r'^(\s*)', nxt).group(1)
    nxt_w = indent_width(nxt_prefix)

    # if next significant line is not more indented than try: => missing try body
    # (covers: except/finally/else same indent, or any statement at same/less indent)
    if nxt_w <= base_w:
        # but avoid double-patching if pass already there immediately (rare)
        out.append(base_prefix + "    pass\n")
        patched += 1

p.write_text("".join(out), encoding="utf-8")
print(f"[OK] inserted pass for missing-indented try blocks: {patched}")
PY

echo "== py_compile =="
python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"
