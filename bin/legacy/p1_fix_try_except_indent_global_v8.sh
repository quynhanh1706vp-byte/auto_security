#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need sed; need nl

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GW" "${GW}.bak_fix_try_except_indent_${TS}"
echo "[BACKUP] ${GW}.bak_fix_try_except_indent_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

re_try = re.compile(r'^(\s*)try\s*:\s*(#.*)?$')
re_except = re.compile(r'^(\s*)(except\b.*:\s*(#.*)?|finally\s*:\s*(#.*)?|else\s*:\s*(#.*)?)$')
re_blank_or_comment = re.compile(r'^\s*(#.*)?$')

try_stack = []  # list of indent strings
out = []
fix_n = 0

def indent_len(s): return len(s.replace("\t","    "))

for i, line in enumerate(lines):
    # pop stack on dedent (skip blanks/comments)
    if not re_blank_or_comment.match(line):
        cur_indent = re.match(r'^(\s*)', line).group(1)
        # dedent: pop tries deeper than current indent
        while try_stack and indent_len(try_stack[-1]) > indent_len(cur_indent):
            try_stack.pop()

    mtry = re_try.match(line)
    if mtry:
        try_stack.append(mtry.group(1))
        out.append(line)
        continue

    mex = re_except.match(line)
    if mex and try_stack:
        cur_indent = mex.group(1)
        want_indent = try_stack[-1]
        # if except/finally/else is indented deeper than its try, fix it
        if indent_len(cur_indent) != indent_len(want_indent):
            fixed = want_indent + mex.group(2).lstrip() + ("\n" if not line.endswith("\n") else "")
            out.append(fixed)
            fix_n += 1
            continue

    out.append(line)

p.write_text("".join(out), encoding="utf-8")
print(f"[OK] fixed indent of except/finally/else: {fix_n}")
PY

echo "== py_compile =="
python3 -m py_compile "$GW" && echo "[OK] py_compile OK" || {
  echo "[ERR] py_compile failed; showing first 140 lines + around error line if any"
  nl -ba "$GW" | sed -n '1,160p'
  exit 3
}
