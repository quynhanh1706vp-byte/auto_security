#!/usr/bin/env bash
set -euo pipefail

BASE="http://127.0.0.1:8910"

RSP="$(curl -sS -X POST "$BASE/api/vsp/run_v1" -H 'Content-Type: application/json' -d '{}')"
RID="$(echo "$RSP" | jq -r '.request_id // .req_id // empty')"
[ -n "$RID" ] || { echo "[ERR] no RID"; echo "$RSP"; exit 1; }

echo "[OK] RID=$RID"

deadline=$((SECONDS+240))
last=""
while [ $SECONDS -lt $deadline ]; do
  J="$(curl -sS "$BASE/api/vsp/run_status_v2/$RID")"
  CI="$(echo "$J" | jq -r '.ci_run_dir // empty')"
  STAGE="$(echo "$J" | jq -r '.stage_name // ""')"
  PCT="$(echo "$J" | jq -r '.progress_pct // 0')"
  KV="$(echo "$J" | jq -r '.kics_verdict // ""')"
  KT="$(echo "$J" | jq -r '.kics_total // 0')"

  echo "[POLL] pct=$PCT stage=$(printf "%q" "$STAGE") ci=$CI kics=($KV,$KT)"

  if [ -n "$CI" ] && [ -f "$CI/kics/kics_summary.json" ]; then
    echo "[OK] kics_summary.json exists"
    cat "$CI/kics/kics_summary.json" | jq .
    echo "[OK] status v2 (final snapshot)"
    echo "$J" | jq '{ok,ci_run_dir,stage_name,progress_pct,kics_verdict,kics_total,kics_counts,degraded_tools}'
    exit 0
  fi
  sleep 3
done

echo "[ERR] timeout waiting for kics_summary.json"
echo "$J" | jq .
exit 2
