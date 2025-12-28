#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_datasource_tab_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_use_v2_${TS}" && echo "[BACKUP] $F.bak_use_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_datasource_tab_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")
s2=s.replace("/api/vsp/findings_unified_v1/", "/api/vsp/findings_unified_v2/")
p.write_text(s2, encoding="utf-8")
print("[OK] datasource now uses findings_unified_v2")
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] Hard refresh Ctrl+Shift+R"
