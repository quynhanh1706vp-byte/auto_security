#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3)"

RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | "$PY" -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "RID=$RID"

echo "== dashboard_v3_latest =="
curl -fsS "$BASE/api/vsp/dashboard_v3_latest?rid=$RID" \
| "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"rid=",j.get("rid"),"kpis_total=",(j.get("kpis") or {}).get("total"),"sev_dist=",len(((j.get("charts") or {}).get("severity_distribution") or [])))'

echo "== dashboard_v3_tables =="
curl -fsS "$BASE/api/vsp/dashboard_v3_tables?rid=$RID" \
| "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"top_findings=",len((((j.get("tables") or {}).get("top_findings")) or [])))'

echo "== dashboard_latest_v1 (if UI calls it) =="
curl -fsS "$BASE/api/vsp/dashboard_latest_v1?rid=$RID" \
| "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"has_kpis=",("kpis" in j), "has_charts=",("charts" in j))' \
|| echo "(dashboard_latest_v1 not available / not used)"

echo "[DONE] p3k_smoke_dashboard_v3_v1"
