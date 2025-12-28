#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="static/js/vsp_bundle_commercial_v2.js"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_dashcomm_${TS}"
echo "[BACKUP] $F.bak_dashcomm_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_DASH_USE_COMMERCIAL_P1_V1"
if MARK in s:
    print("[OK] already patched:", MARK); raise SystemExit(0)

# thay loadDashboard() fetch dashboard_v3 -> try commercial then fallback
pat=re.compile(r"async function loadDashboard\(\)\s*\{.*?\n\}", re.S)
m=pat.search(s)
if not m:
    print("[ERR] cannot find loadDashboard()"); raise SystemExit(2)

new = r'''
async function loadDashboard(){
  try{
    // {MARK}
    STATE.dashboard = await fetchJson('/api/vsp/dashboard_commercial_v1?ts=' + Date.now());
  }catch(e1){
    try{
      STATE.dashboard = await fetchJson('/api/vsp/dashboard_v3?ts=' + Date.now());
    }catch(e2){
      STATE.degraded.push('dashboard_commercial_v1');
      STATE.dashboard = null;
    }
  }
  setDegraded();
}
'''.replace("{MARK}", MARK)

s2=s[:m.start()]+new+s[m.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

node --check "$F"
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh
