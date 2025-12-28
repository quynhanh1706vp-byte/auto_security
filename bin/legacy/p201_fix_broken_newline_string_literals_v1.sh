#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p201_${TS}"
echo "[OK] backup: ${F}.bak_p201_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("static/js/vsp_c_common_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
orig = s

# Fix illegal newline inside a double-quoted string for common ops:
# split(" <NEWLINE> ")  => split("\\n")
# join(" <NEWLINE> ")   => join("\\n")
# replace(" <NEWLINE> " => replace("\\n"
# (we keep it narrow: only when the string literal is exactly a raw newline)
def fix_op(op: str, text: str) -> str:
    # op( " \n " )
    pat = re.compile(rf'({op}\s*\(\s*")\s*\n\s*("\s*\))')
    return pat.sub(rf'{op}("\\n")', text)

# But in your file, it looks like: txt.split(" <newline> ... (unterminated)
# so also fix the literal pattern split(" \n
pat_unterminated = re.compile(r'split\(\s*"\s*\n')
s = pat_unterminated.sub('split("\\n")', s)

for op in ["split", "join"]:
    s = fix_op(op, s)

# In case there are replace(" \n ") too
pat_replace = re.compile(r'replace\(\s*"\s*\n\s*"\s*,')
s = pat_replace.sub('replace("\\n",', s)

if s == orig:
    print("[WARN] no broken newline string literal pattern found (maybe different corruption)")
else:
    p.write_text(s, encoding="utf-8")
    print("[OK] fixed broken newline-in-string patterns")
PY

echo "== [CHECK] node --check =="
if command -v node >/dev/null 2>&1; then
  node --check "$F"
  echo "[OK] JS syntax OK"
else
  echo "[WARN] node not found; skipped syntax check"
fi

echo ""
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
