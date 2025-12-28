#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_gate_panel_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$F" ] || { echo "[SKIP] missing $F"; exit 0; }

cp -f "$F" "$F.bak_p0_gate_${TS}"
echo "[BACKUP] $F.bak_p0_gate_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_gate_panel_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")
orig = s
s = s.replace("filter=1", "filter=0")
s = s.replace("hide_empty=1", "hide_empty=0")
if s != orig:
    p.write_text(s, encoding="utf-8")
    print("[OK] loosened filter/hide_empty in", p)
else:
    print("[OK] no change needed for", p)
PY

node --check "$F" >/dev/null
echo "[OK] node --check $F"
