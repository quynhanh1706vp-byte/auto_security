#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need node
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_kpirid_${TS}"
echo "[BACKUP] ${JS}.bak_kpirid_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_luxe_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_DASH_FETCH_KPI_WITH_RID_LATEST_V1"
if MARK in s:
    print("[OK] already patched:", MARK); raise SystemExit(0)

patch = r'''
/* VSP_P0_DASH_FETCH_KPI_WITH_RID_LATEST_V1 */
async function vspGetRidLatestSafe(){
  try{
    const r = await fetch("/api/vsp/rid_latest", {cache:"no-store"});
    const j = await r.json();
    return (j && j.rid) ? String(j.rid) : "";
  }catch(e){ return ""; }
}
function vspWithRid(url, rid){
  if(!rid) return url;
  return url + (url.includes("?") ? "&" : "?") + "rid=" + encodeURIComponent(rid);
}
'''

# Insert patch near top (after first "use strict" or first function)
insert_at = 0
m = re.search(r'(?m)^\s*["\']use strict["\'];\s*$', s)
if m: insert_at = m.end()
s2 = s[:insert_at] + "\n" + patch + "\n" + s[insert_at:]

# Replace raw fetches to dash_kpis/dash_charts to include rid_latest (best-effort)
# We handle both "/api/vsp/dash_kpis" and "api/vsp/dash_kpis"
def repl(url):
    return f'vspWithRid("{url}", (window.__vsp_rid_latest||""))'

# Ensure we have a bootstrap that sets window.__vsp_rid_latest once
boot = r'''
/* VSP_P0_DASH_RID_BOOTSTRAP_V1 */
(async ()=>{ try{ window.__vsp_rid_latest = await vspGetRidLatestSafe(); }catch(e){} })();
'''
if "VSP_P0_DASH_RID_BOOTSTRAP_V1" not in s2:
    s2 = s2 + "\n" + boot + "\n"

# Very conservative string replace:
s2 = s2.replace('"/api/vsp/dash_kpis"', repl("/api/vsp/dash_kpis"))
s2 = s2.replace('"/api/vsp/dash_charts"', repl("/api/vsp/dash_charts"))

p.write_text(s2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

node --check "$JS" >/dev/null
echo "[OK] node --check passed"

# bump asset_v if you use it
bash -lc 'bash bin/p1_set_asset_v_runtime_ts_v1.sh >/dev/null 2>&1 || true'
systemctl restart "$SVC" 2>/dev/null || true

echo "== QUICK VERIFY =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "RID=$RID"
curl -fsS "$BASE/api/vsp/dash_kpis?rid=$RID" | head -c 260; echo
curl -fsS "$BASE/api/vsp/dash_charts?rid=$RID" | head -c 260; echo
