#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p46_gate_pack_handover_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need head; need bash

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fixfind_${TS}"
echo "[BACKUP] ${F}.bak_fixfind_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("bin/p46_gate_pack_handover_v1.sh")
s=p.read_text(encoding="utf-8", errors="replace")

# Replace the problematic find invocation order:
# find . -type f -maxdepth 6 ...
# -> find . -maxdepth 6 -type f ...
pat = r'find\s+\.\s+-type\s+f\s+-maxdepth\s+6\s+!\s+-name\s+"SHA256SUMS\.txt"\s+-print0'
rep = r'find . -maxdepth 6 -type f ! -name "SHA256SUMS.txt" -print0'

new, n = re.subn(pat, rep, s)
if n == 0:
    # also try a looser match in case spacing differs
    pat2 = r'find\s+\.\s+-type\s+f\s+-maxdepth\s+6\s+!\s+-name\s+"SHA256SUMS\.txt"\s+-print0\s*\\?'
    new2, n2 = re.subn(pat2, rep, s)
    if n2 == 0:
        print("[ERR] could not locate the find -maxdepth pattern to patch")
        raise SystemExit(2)
    new, n = new2, n2

p.write_text(new, encoding="utf-8")
print(f"[OK] patched find order (count={n})")
PY

# Quick syntax check
bash -n "$F" && echo "[OK] bash -n PASS: $F"

# Show the patched block for sanity
echo "== [SNIP] SHA256SUMS block =="
grep -n "SHA256SUMS" -n "$F" | head -n 30
