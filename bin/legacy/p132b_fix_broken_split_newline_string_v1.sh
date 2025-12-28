#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p132b_${TS}"
echo "[OK] backup => ${F}.bak_p132b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_c_common_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

before = s

# Fix patterns like: split(" <NEWLINE> ")  or split(' <NEWLINE> ')
# where the newline is literally inside quotes (broken JS)
s = re.sub(r'split\("\s*\n\s*"\)', r'split("\\n")', s, flags=re.M)
s = re.sub(r"split\('\s*\n\s*'\)", r'split("\\n")', s, flags=re.M)

# Also fix the common case: split(" <NEWLINE> ").length (extra safe)
s = re.sub(r'split\("\s*\n\s*"\)\s*\.length', r'split("\\n").length', s, flags=re.M)
s = re.sub(r"split\('\s*\n\s*'\)\s*\.length", r'split("\\n").length', s, flags=re.M)

changed = (s != before)
if not changed:
    print("[WARN] no broken split pattern found (maybe different break).")
else:
    p.write_text(s, encoding="utf-8")
    print("[OK] patched broken split-newline string(s).")

# Print a small grep-like snippet for verification
lines = s.splitlines()
hits=[]
for i,ln in enumerate(lines, start=1):
    if "split(" in ln and "\\n" in ln and "txt.split" in ln:
        hits.append((i, ln.strip()))
print("[INFO] sample lines containing txt.split(\\n):")
for i,ln in hits[:8]:
    print(f"  L{i}: {ln[:140]}")
PY

if command -v node >/dev/null 2>&1; then
  echo "== [CHECK] node --check =="
  node --check "$F"
  echo "[OK] JS syntax OK"
fi

echo
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
