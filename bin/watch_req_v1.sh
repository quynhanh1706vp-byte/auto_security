#!/usr/bin/env bash
set -euo pipefail
REQ="${1:-}"
[ -n "$REQ" ] || { echo "Usage: $0 <REQ_ID>"; exit 1; }

API="http://localhost:8910"

while true; do
  j="$(curl -s "$API/api/vsp/run_status_v1/$REQ")"
  echo "$j" | jq '{req_id,status,final,exit_code,gate,ci_run_dir,vsp_run_id,flag,sync}'
  RUN_DIR="$(echo "$j" | jq -r '.ci_run_dir')"
  if [ -n "$RUN_DIR" ] && [ "$RUN_DIR" != "null" ]; then
    echo "---- tail kics.log ----"
    tail -n 15 "$RUN_DIR/kics/kics.log" 2>/dev/null || true
  fi
  if [ "$(echo "$j" | jq -r '.final')" = "true" ]; then
    echo "=== FINAL TAIL (last 120) ==="
    echo "$j" | jq -r '.tail' | tail -n 120
    echo "=== FS runs (latest) ==="
    curl -s "$API/api/vsp/runs_index_v3_fs?limit=1&hide_empty=1" | jq '.items[0]'
    exit 0
  fi
  sleep 5
done
