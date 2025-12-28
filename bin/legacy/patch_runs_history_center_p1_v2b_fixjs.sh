#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_history_center_v2b_${TS}" && echo "[BACKUP] $F.bak_history_center_v2b_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

# Fix the exact bad JS token "or False" introduced previously
if "or False" in s:
    s = s.replace("or False", "|| false")
    print("[OK] replaced 'or False' -> '|| false'")
else:
    print("[WARN] no 'or False' found")

# Also fix any accidental " or True" if present (defensive)
if " or True" in s:
    s = s.replace(" or True", " || true")
    print("[OK] replaced 'or True' -> '|| true'")

p.write_text(s, encoding="utf-8")
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK => $F"
echo "[DONE] patch_runs_history_center_p1_v2b_fixjs"
echo "Next: hard refresh browser (Ctrl+Shift+R)."
