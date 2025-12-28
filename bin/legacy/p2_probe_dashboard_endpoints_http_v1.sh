#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${1:-}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3

if [ -z "$RID" ]; then
  RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
fi
echo "[INFO] RID=$RID"

eps=(
  "/api/vsp/run_gate_summary_v1"
  "/api/vsp/top_findings_v1"
  "/api/vsp/trend_v1"
  "/api/vsp/top_cwe_exposure_v1"
  "/api/vsp/critical_high_by_tool_v1"
  "/api/vsp/top_risk_findings_v1"
  "/api/vsp/tool_buckets_v1"
)

for ep in "${eps[@]}"; do
  url="$BASE$ep?rid=$RID&limit=20"
  code="$(curl -sS -o /tmp/vsp_ep_probe.$$ -w "%{http_code}" "$url" || true)"
  printf "%-35s => %s\n" "$ep" "$code"
done
rm -f /tmp/vsp_ep_probe.$$ 2>/dev/null || true
