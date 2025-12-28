#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fixsyntax_${TS}"
echo "[BACKUP] ${F}.bak_fixsyntax_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")
orig = s

MARK="VSP_P1_FIX_SUMMARY_SHA_SYNTAX_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Fix patterns like:
#   if _n == "SUMMARY.txt", "SHA256SUMS.txt":
#   if _n == 'SUMMARY.txt', 'SHA256SUMS.txt':
pat = re.compile(
    r'^(?P<indent>\s*)if\s+(?P<var>[A-Za-z_]\w*)\s*==\s*(?P<a>"SUMMARY\.txt"|\'SUMMARY\.txt\')\s*,\s*(?P<b>"SHA256SUMS\.txt"|\'SHA256SUMS\.txt\')\s*:\s*$',
    re.M
)
s = pat.sub(r'\g<indent>if \g<var> in ("SUMMARY.txt","SHA256SUMS.txt"):', s)

# Also fix same bug but with reports/ prefix
pat2 = re.compile(
    r'^(?P<indent>\s*)if\s+(?P<var>[A-Za-z_]\w*)\s*==\s*(?P<a>"reports/SUMMARY\.txt"|\'reports/SUMMARY\.txt\')\s*,\s*(?P<b>"reports/SHA256SUMS\.txt"|\'reports/SHA256SUMS\.txt\')\s*:\s*$',
    re.M
)
s = pat2.sub(r'\g<indent>if \g<var> in ("reports/SUMMARY.txt","reports/SHA256SUMS.txt"):', s)

# Safety: catch accidental tuple-compare style "== ('a','b')" (rare)
s = re.sub(
    r'^(?P<indent>\s*)if\s+(?P<var>[A-Za-z_]\w*)\s*==\s*\(\s*(?P<a>["\']SUMMARY\.txt["\'])\s*,\s*(?P<b>["\']SHA256SUMS\.txt["\'])\s*\)\s*:\s*$',
    r'\g<indent>if \g<var> in ("SUMMARY.txt","SHA256SUMS.txt"):',
    s, flags=re.M
)

if s == orig:
    print("[WARN] no change made (pattern not found).")
else:
    s = s + f"\n# {MARK}\n"
    p.write_text(s, encoding="utf-8")
    print("[OK] patched:", MARK)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK: vsp_demo_app.py"

sudo systemctl restart vsp-ui-8910.service
sleep 1
sudo systemctl --no-pager -l status vsp-ui-8910.service || true
