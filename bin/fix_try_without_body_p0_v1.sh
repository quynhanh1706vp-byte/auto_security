#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_try_${TS}"
echo "[BACKUP] $F.bak_fix_try_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

def is_blank_or_comment(s: str) -> bool:
    t = s.strip()
    return (t == "") or t.startswith("#")

def indent_of(s: str) -> str:
    return re.match(r"^\s*", s).group(0)

changed = 0
out = []
i = 0
n = len(lines)

while i < n:
    ln = lines[i]
    m_try = re.match(r"^(\s*)try\s*:\s*(#.*)?\n?$", ln)
    if not m_try:
        out.append(ln)
        i += 1
        continue

    base_indent = m_try.group(1)
    out.append(ln)

    # look ahead to next non-blank/comment line
    j = i + 1
    while j < n and is_blank_or_comment(lines[j]):
        out.append(lines[j])
        j += 1

    if j >= n:
        # EOF after try: -> insert pass
        out.append(base_indent + "    pass\n")
        changed += 1
        break

    next_ln = lines[j]
    # if next is except/finally at same indent => missing try body
    if re.match(r"^" + re.escape(base_indent) + r"(except\b|finally\b)", next_ln):
        out.append(base_indent + "    pass\n")
        changed += 1
        # then continue normal loop from j (do not consume next_ln here)
        i = j
        continue

    # otherwise normal: do not consume next_ln (it will be processed in loop)
    i += 1

p.write_text("".join(out), encoding="utf-8")
print(f"[OK] inserted pass for empty try blocks: {changed}")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[NEXT] try import:"
echo "  python3 -c 'import wsgi_vsp_ui_gateway; print(\"wsgi ok\")'"
