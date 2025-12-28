#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_fix_v3cc_${TS}"
echo "[BACKUP] ${F}.bak_fix_v3cc_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_dashboard_luxe_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
s2=s.replace("/api/vsp/top_findings_v3cc", "/api/vsp/top_findings_v3c")
p.write_text(s2, encoding="utf-8")
print("[OK] replaced v3cc -> v3c")
PY

echo "[NEXT] Ctrl+F5 /vsp5"
