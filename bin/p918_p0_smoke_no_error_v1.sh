#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci/p918_smoke_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

hit(){
  local url="$1"
  local code
  code="$(curl -sS -o "$OUT/body.tmp" -w "%{http_code}" --max-time 6 "$url" || true)"
  printf "%-55s %s\n" "$url" "$code" | tee -a "$OUT/summary.txt"
  if [[ "$code" != "200" ]]; then
    echo "[FAIL] $url => $code" | tee -a "$OUT/summary.txt"
    head -n 50 "$OUT/body.tmp" > "$OUT/last_body.txt" || true
    exit 2
  fi
}

echo "== [P918] UI tabs =="
hit "$BASE/vsp5"
hit "$BASE/runs"
hit "$BASE/data_source"
hit "$BASE/c/settings"
hit "$BASE/c/rule_overrides"

echo "== [P918] APIs (must be 200 + JSON) =="
hit "$BASE/api/vsp/runs_v3?limit=5&include_ci=1"
hit "$BASE/api/vsp/top_findings_v2?limit=5"
hit "$BASE/api/vsp/dashboard_kpis_v4"
hit "$BASE/api/vsp/trend_v1"
hit "$BASE/api/vsp/exports_v1"
hit "$BASE/api/vsp/run_status_v1"
hit "$BASE/api/vsp/ops_latest_v1"

echo "[OK] P918 smoke PASS. Evidence: $OUT"
