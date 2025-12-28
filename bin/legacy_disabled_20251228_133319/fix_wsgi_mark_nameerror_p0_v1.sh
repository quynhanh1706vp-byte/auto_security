#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fix_mark_${TS}"
echo "[BACKUP] ${F}.bak_fix_mark_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

# 1) Ensure a GLOBAL MARK exists (fixes NameError in older MW blocks)
FIXTAG="VSP_GLOBAL_MARK_FIX_P0_V1"
if FIXTAG not in s:
    # insert after last import block (best-effort)
    lines=s.splitlines(True)
    ins_i=0
    for i,ln in enumerate(lines[:300]):
        if ln.startswith("import ") or ln.startswith("from "):
            ins_i=i+1
    inject = f'\n# {FIXTAG}\nMARK = "VSP_MARK_P0"\n\n'
    lines.insert(ins_i, inject)
    s="".join(lines)

# 2) Make fallback V2 not depend on MARK variable for rendering/headers
# Replace f"Marker: {MARK}\n{why}</pre>" -> literal marker line
s = s.replace('f"Marker: {MARK}\\n{why}</pre>"',
              'f"Marker: VSP_RUNS_500_FALLBACK_MW_P0_V2\\n{why}</pre>"')

# Replace ("X-VSP-RUNS-FALLBACK", MARK) -> literal marker header
s = s.replace('("X-VSP-RUNS-FALLBACK", MARK)',
              '("X-VSP-RUNS-FALLBACK", "VSP_RUNS_500_FALLBACK_MW_P0_V2")')

p.write_text(s, encoding="utf-8")
print("[OK] injected global MARK + hardened fallback marker")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"

echo "== restart =="
/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_clean_p0_v2.sh

echo "== verify /runs =="
curl -sS -I http://127.0.0.1:8910/runs | head -n 30
echo
curl -sS http://127.0.0.1:8910/runs | grep -n "VSP_RUNS_500_FALLBACK_MW_P0_V2|VSP_RUNS_500_FALLBACK_MW_P0_V1|VSP_MARK_P0" | head -n 40 || true
