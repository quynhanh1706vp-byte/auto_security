#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

RID="${1:-}"
if [ -z "${RID}" ]; then
  RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
fi
echo "RID=$RID"

echo "== dash_kpis =="
curl -fsS "$BASE/api/vsp/dash_kpis?rid=$RID" | head -c 400; echo
echo "== dash_charts =="
curl -fsS "$BASE/api/vsp/dash_charts?rid=$RID" | head -c 400; echo

echo
echo "== try run_file_allow on candidate paths =="
cands=(
  "findings_unified.json"
  "reports/findings_unified.json"
  "report/findings_unified.json"
  "run_gate_summary.json"
  "reports/run_gate_summary.json"
  "report/run_gate_summary.json"
  "run_gate.json"
  "reports/run_gate.json"
  "report/run_gate.json"
)

for p in "${cands[@]}"; do
  echo "-- $p --"
  curl -sS "$BASE/api/vsp/run_file_allow?rid=$RID&path=$p&limit=1" \
  | python3 - <<'PY' 2>/dev/null || true
import sys,json
try:
  j=json.load(sys.stdin)
  ok=j.get("ok", None)
  if ok is False:
    print("ok=false err=", j.get("err"))
  else:
    # run_file_allow thường trả {meta, findings} hoặc dict json file
    meta=j.get("meta") or {}
    counts=(meta.get("counts_by_severity") or meta.get("counts_total") or {})
    if counts:
      print("ok=true meta_counts=", counts)
    else:
      # print keys only
      print("ok=true keys=", list(j.keys())[:12])
except Exception as e:
  print("parse_fail", repr(e))
PY
done
