#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_markfix_v3_${TS}"
echo "[BACKUP] ${F}.bak_markfix_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

TAG="VSP_MARK_FIX_P0_V3"

# 1) FORCE insert global MARK/MARKB near the very top (after module docstring if any)
if TAG not in s:
    # keep shebang/encoding lines
    lines=s.splitlines(True)
    i=0
    if i < len(lines) and lines[i].startswith("#!"):
        i += 1
    if i < len(lines) and "coding" in lines[i]:
        i += 1

    # skip blank/comment lines
    while i < len(lines) and (lines[i].strip()=="" or lines[i].lstrip().startswith("#")):
        i += 1

    # skip module docstring if present
    if i < len(lines) and lines[i].lstrip().startswith(('"""',"'''")):
        q = lines[i].lstrip()[:3]
        i += 1
        while i < len(lines) and q not in lines[i]:
            i += 1
        if i < len(lines):
            i += 1

    inject = (
        f"\n# {TAG}\n"
        "MARK = \"VSP_MARK_P0\"\n"
        "MARKB = b\"VSP_MARK_P0\"\n\n"
    )
    lines.insert(i, inject)
    s="".join(lines)

# 2) Replace ALL MARK.encode(...) to MARKB (covers MARK.encode(), MARK.encode('utf-8'), etc.)
s = re.sub(r'\bMARK\.encode\([^\)]*\)', 'MARKB', s)

# 3) Harden fallback strings/headers not to reference MARK
s = s.replace('f"Marker: {MARK}\\n{why}</pre>"',
              'f"Marker: VSP_RUNS_500_FALLBACK_MW_P0_V2\\n{why}</pre>"')
s = s.replace('("X-VSP-RUNS-FALLBACK", MARK)',
              '("X-VSP-RUNS-FALLBACK", "VSP_RUNS_500_FALLBACK_MW_P0_V2")')

p.write_text(s, encoding="utf-8")
print("[OK] forced global MARK/MARKB + replaced MARK.encode(*) -> MARKB")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"

echo "[NEXT] restart + live verify"
