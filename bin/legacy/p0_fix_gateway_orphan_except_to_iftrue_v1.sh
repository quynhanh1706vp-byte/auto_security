#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_orphan_except_${TS}"
echo "[BACKUP] ${F}.bak_orphan_except_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

try_re = re.compile(r'^\s*try:\s*(#.*)?$')
ctrl_re = re.compile(r'^(\s*)(except\b|finally\b|else\b)\b.*:\s*(#.*)?$')

def is_significant(s: str) -> bool:
    t = s.strip()
    return t != "" and not t.startswith("#")

def indent_width(prefix: str) -> int:
    return len(prefix.replace("\t", "    "))

patched = 0
out = lines[:]  # in-place editable

for i, line in enumerate(lines):
    m = ctrl_re.match(line)
    if not m:
        continue
    indent = m.group(1)
    kw = m.group(2)
    iw = indent_width(indent)

    # find previous significant line
    j = i - 1
    while j >= 0 and not is_significant(lines[j]):
        j -= 1
    if j < 0:
        prev_is_try_same_indent = False
    else:
        prev = lines[j]
        prev_indent = re.match(r'^(\s*)', prev).group(1)
        prev_is_try_same_indent = (indent_width(prev_indent) == iw and bool(try_re.match(prev)))

    if not prev_is_try_same_indent:
        out[i] = f"{indent}if True:  # VSP_AUTOFIX_ORPHAN_{kw.upper()}_V1\n"
        patched += 1

p.write_text("".join(out), encoding="utf-8")
print(f"[OK] replaced orphan except/finally/else -> if True: {patched}")
PY

echo "== py_compile =="
python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"
