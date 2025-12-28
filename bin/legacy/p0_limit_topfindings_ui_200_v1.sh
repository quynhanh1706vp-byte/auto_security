#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_dashboard_luxe_v1.js"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_top200_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_dashboard_luxe_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

# Replace common patterns: limit=2500 -> limit=200
s2 = re.sub(r'limit=2500\b', 'limit=200', s)

# If no explicit limit=2500, still add a hard slice safeguard for arrays named items/findings
if s2 == s:
    # best-effort: after any "items = ..." or "findings = ..." add slice(0,200) if array
    s2 = re.sub(r'(?m)^(?P<ind>\s*)(?P<var>(items|findings|rows))\s*=\s*(?P<rhs>.+);\s*$',
                r'\g<ind>\g<var> = \g<rhs>;\n\g<ind>if (Array.isArray(\g<var>) && \g<var>.length > 200) { \g<var> = \g<var>.slice(0, 200); }',
                s2, count=1)

p.write_text(s2, encoding="utf-8")
print("[OK] patched", p)
PY

echo "[OK] patched top findings UI -> 200 (Ctrl+F5)"
