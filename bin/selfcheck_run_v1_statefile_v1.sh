#!/usr/bin/env bash
set -euo pipefail

BASE="http://127.0.0.1:8910"
RSP="$(curl -sS -X POST "$BASE/api/vsp/run_v1" -H 'Content-Type: application/json' -d '{}')"
echo "$RSP" | jq .

RID="$(echo "$RSP" | jq -r '.request_id // .req_id')"
echo "RID=$RID"

for i in 1 2 3 4 5; do
  echo "== poll $i =="
  curl -sS "$BASE/api/vsp/run_status_v1/$RID" | jq '{ok,status,final,stage_index,stage_total,stage_name,progress_pct,ci_run_dir,error}'
  sleep 2
done

S1="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_req_state/${RID}.json"
S2="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1/${RID}.json"

echo "== state file check =="
if [ -f "$S1" ]; then
  echo "[OK] ui_req_state: $S1"
  jq '{req_id,status,final,stage_name,ci_run_dir}' "$S1"
elif [ -f "$S2" ]; then
  echo "[OK] uireq_v1: $S2"
  jq '{req_id,status,final,stage_name,ci_run_dir}' "$S2"
else
  echo "[ERR] state json not found in ui_req_state/ or uireq_v1/"
  ls -la /home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1 2>/dev/null | tail -n 5 || true
  exit 2
fi
