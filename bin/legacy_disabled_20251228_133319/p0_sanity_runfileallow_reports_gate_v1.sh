#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID_FALLBACK="RUN_20251120_130310"

echo "== wait /api/ui/runs_kpi_v2 =="
OK=0
for _ in $(seq 1 30); do
  J="$(curl -fsS "$BASE/api/ui/runs_kpi_v2?days=30" 2>/dev/null || true)"
  if echo "$J" | grep -q '"ok": true'; then OK=1; break; fi
  sleep 0.3
done
[ "$OK" -eq 1 ] || { echo "[WARN] KPI endpoint not ready, continue anyway"; }

echo "== try get RID from /api/vsp/runs (no python parse if empty) =="
RID=""
RJSON="$(curl -fsS "$BASE/api/vsp/runs?limit=1" 2>/dev/null || true)"
if echo "$RJSON" | grep -q '"run_id"'; then
  RID="$(python3 - <<PY
import json,sys
j=json.loads("""$RJSON""")
print(j["items"][0]["run_id"])
PY
)"
fi
[ -n "$RID" ] || RID="$RID_FALLBACK"
echo "[RID]=$RID"

echo "== sanity run_file_allow reports/run_gate_summary.json =="
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 80
