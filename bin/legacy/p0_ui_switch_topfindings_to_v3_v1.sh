#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "${F}.bak_topv3_${TS}"
echo "[BACKUP] ${F}.bak_topv3_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_dashboard_luxe_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
s2=s.replace("/api/vsp/top_findings_v1", "/api/vsp/top_findings_v3")
p.write_text(s2, encoding="utf-8")
print("[OK] switched top_findings_v1 -> v3 in", p)
PY

echo "[DONE] Ctrl+F5 on browser"
