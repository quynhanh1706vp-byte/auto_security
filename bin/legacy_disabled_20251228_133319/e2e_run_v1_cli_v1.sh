#!/usr/bin/env bash
set -euo pipefail

API="http://localhost:8910"
TARGET="/home/test/Data/SECURITY-10-10-v4"
PROFILE="FULL_EXT"

echo "[E2E] POST /api/vsp/run_v1 ..."
REQ_ID="$(
  curl -s -X POST "$API/api/vsp/run_v1" \
    -H "Content-Type: application/json" \
    -d "{\"mode\":\"local\",\"profile\":\"$PROFILE\",\"target_type\":\"path\",\"target\":\"$TARGET\"}" \
  | jq -r '.req_id'
)"
echo "[E2E] REQ_ID=$REQ_ID"
[ -n "$REQ_ID" ] && [ "$REQ_ID" != "null" ]

echo "[E2E] Polling /api/vsp/run_status_v1/$REQ_ID ..."
while true; do
  j="$(curl -s "$API/api/vsp/run_status_v1/$REQ_ID")"
  echo "$j" | jq '{req_id,status,final,exit_code,gate,ci_run_dir,vsp_run_id,flag,sync}'
  if [ "$(echo "$j" | jq -r '.final')" = "true" ]; then
    echo "=== FINAL TAIL (last 80) ==="
    echo "$j" | jq -r '.tail' | tail -n 80
    echo "=== VERIFY LATEST RUNS (FS) ==="
    curl -s "$API/api/vsp/runs_index_v3_fs?limit=1&hide_empty=1" | jq '.items[0]'
    break
  fi
  sleep 2
done
