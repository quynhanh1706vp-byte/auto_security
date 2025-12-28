#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p127b_${TS}"
echo "[OK] backup: ${F}.bak_p127b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_c_common_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
orig=s

# Fix broken: txt.split(" <newline> ").length  -> txt.split("\n").length
# Handle both " and ' quotes, allow spaces around the newline
s2 = re.sub(r'txt\.split\(\s*"\s*\r?\n\s*"\s*\)\.length', r'txt.split("\\n").length', s, flags=re.M)
s2 = re.sub(r"txt\.split\(\s*'\s*\r?\n\s*'\s*\)\.length", r'txt.split("\\n").length', s2, flags=re.M)

# Also fix any accidental: split(" \n ").  (rare)
s2 = re.sub(r'\.split\(\s*"\s*\r?\n\s*"\s*\)', r'.split("\\n")', s2, flags=re.M)
s2 = re.sub(r"\.split\(\s*'\s*\r?\n\s*'\s*\)", r'.split("\\n")', s2, flags=re.M)

if s2 == orig:
    print("[WARN] no change matched; showing nearby 'split(' occurrences for manual check:")
    for m in re.finditer(r'split\(', s):
        line = s.count("\n", 0, m.start()) + 1
        print(" - line", line)
else:
    p.write_text(s2, encoding="utf-8")
    print("[OK] fixed broken split newline token")

# Print the exact line that contains 'const lines' (first occurrence)
t = p.read_text(encoding="utf-8", errors="replace")
m = re.search(r'^\s*const\s+lines\s*=.*$', t, flags=re.M)
if m:
    print("[INFO] lines_stmt:", m.group(0).strip())
PY

if command -v node >/dev/null 2>&1; then
  node --check "$F" && echo "[OK] JS syntax OK"
else
  echo "[WARN] node not found; skipped node --check"
fi

echo
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
echo "  http://127.0.0.1:8910/c/runs"
