#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3

RID="$(curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json;print(json.load(sys.stdin)["rid"])')"
echo "RID=$RID"

check(){
  local p="$1"
  local code
  code="$(curl -sS -o /dev/null -w "%{http_code}" "$BASE/api/vsp/run_file_allow?rid=$RID&path=$p" || true)"
  printf "%-35s => %s\n" "$p" "$code"
}

echo "== probe common findings paths =="
check "findings_unified.json"
check "reports/findings_unified.json"
check "reports/findings_unified.csv"
check "findings_unified.sarif"
check "reports/findings_unified.sarif"
check "run_gate.json"
check "run_gate_summary.json"
