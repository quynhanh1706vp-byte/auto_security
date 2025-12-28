#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_remove_mark_refs_${TS}"
echo "[BACKUP] ${F}.bak_remove_mark_refs_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

TAG="VSP_REMOVE_MARK_REFS_P0_V4"
if TAG in s:
    print("[OK] already patched"); raise SystemExit(0)

# 1) Replace ALL MARK.encode(...) -> b"VSP_MARK_P0"
s2 = re.sub(r'\bMARK\.encode\([^\)]*\)', 'b"VSP_MARK_P0"', s)
s2 = re.sub(r'\bMARK\.encode\(\)', 'b"VSP_MARK_P0"', s2)

# 2) Replace any plain "Marker: {MARK}" in fallback to constant marker (so fallback can't crash)
s2 = s2.replace('f"Marker: {MARK}\\n{why}</pre>"',
                'f"Marker: VSP_RUNS_500_FALLBACK_MW_P0_V2\\n{why}</pre>"')

# 3) Replace any header tuple using MARK
s2 = re.sub(r'\("X-VSP-RUNS-FALLBACK"\s*,\s*MARK\)',
            '("X-VSP-RUNS-FALLBACK","VSP_RUNS_500_FALLBACK_MW_P0_V2")',
            s2)

# 4) Replace any HTML id/data marker that uses {MARK} (prevents NameError if some block uses MARK in f-string building)
# We only target the obvious patterns that were introduced by quick-export/fallback attempts.
s2 = s2.replace('id="{MARK}"', 'id="VSP_MARK_P0"')
s2 = s2.replace('data-vsp-marker="{MARK}"', 'data-vsp-marker="VSP_MARK_P0"')

if s2 == s:
    raise SystemExit("[ERR] no changes made (did not find MARK.encode / marker patterns)")

p.write_text(s2 + f"\n# {TAG}\n", encoding="utf-8")
print("[OK] patched: removed MARK refs that cause NameError")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"

echo "[NEXT] restart + verify"
