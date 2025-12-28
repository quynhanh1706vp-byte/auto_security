#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_harden_mark_${TS}"
echo "[BACKUP] ${F}.bak_harden_mark_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

TAG="VSP_HARDEN_MARK_P0_V2"

# (1) Ensure global MARK + MARKB exist (module-scope)
if TAG not in s:
    lines=s.splitlines(True)

    # insert right after imports block (first ~350 lines)
    ins=0
    for i,ln in enumerate(lines[:350]):
        if ln.startswith("import ") or ln.startswith("from "):
            ins=i+1

    inject = (
        f"\n# {TAG}\n"
        "MARK = \"VSP_MARK_P0\"\n"
        "MARKB = MARK.encode(\"utf-8\", \"replace\")\n\n"
    )
    lines.insert(ins, inject)
    s="".join(lines)

# (2) Replace MARK.encode() -> MARKB everywhere (kills NameError even if MARK was missing in old blocks)
s = s.replace("MARK.encode()", "MARKB")

# (3) Harden fallback V2 to not reference MARK in strings/headers
s = re.sub(r'X-VSP-RUNS-FALLBACK"\s*,\s*MARK\b',
           'X-VSP-RUNS-FALLBACK", "VSP_RUNS_500_FALLBACK_MW_P0_V2"',
           s)

# Replace any f"Marker: {MARK}\n{why}</pre>" pattern (a few variants)
s = s.replace('f"Marker: {MARK}\\n{why}</pre>"',
              'f"Marker: VSP_RUNS_500_FALLBACK_MW_P0_V2\\n{why}</pre>"')
s = s.replace('f"Marker: {MARK}\\n{why}</pre>"',
              'f"Marker: VSP_RUNS_500_FALLBACK_MW_P0_V2\\n{why}</pre>"')

p.write_text(s, encoding="utf-8")
print("[OK] hardened MARK: global MARK/MARKB + replaced MARK.encode()->MARKB")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"
