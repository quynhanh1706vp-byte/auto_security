#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3

echo "== /vsp5 html includes bundle =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_bundle_commercial_v2.js" | head -n 3

echo "== latest rid =="
RID="$(curl -fsS "$BASE/api/vsp/latest_rid" | python3 -c 'import sys,json; print(json.load(sys.stdin)["rid"])')"
echo "RID=$RID"

echo "== rid_latest_gate_root =="
curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"rid=",j.get("rid"),"gate_root=",j.get("gate_root"))'

echo "== run_file_allow MUST 200 for core dashboard files =="
for p in run_gate_summary.json findings_unified.json run_gate.json run_manifest.json run_evidence_index.json; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" "$BASE/api/vsp/run_file_allow?rid=$RID&path=$p" || true)"
  echo "$p => $code"
done

echo "== reports (optional but should be allowed for dashboard actions) =="
for p in reports/findings_unified.csv reports/findings_unified.sarif reports/findings_unified.html; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" "$BASE/api/vsp/run_file_allow?rid=$RID&path=$p" || true)"
  echo "$p => $code"
done

echo "[DONE] If any core file !=200 => dashboard will be broken."
