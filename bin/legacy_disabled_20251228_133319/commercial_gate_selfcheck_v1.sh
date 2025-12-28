#!/usr/bin/env bash
set -euo pipefail
BASE="http://127.0.0.1:8910"

echo "== health =="
curl -sS -o /dev/null -w "HTTP=%{http_code}\n" "$BASE/" 

echo "== run_v1 =="
RSP="$(curl -sS -X POST "$BASE/api/vsp/run_v1" -H 'Content-Type: application/json' -d '{}')"
RID="$(echo "$RSP" | jq -r '.request_id')"
echo "RID=$RID"

sleep 2

echo "== status must have kics_tail (at least empty string) =="
curl -sS "$BASE/api/vsp/run_status_v1/$RID" \
 | jq '{has_kics_tail:has("kics_tail"), kics_tail_len:(.kics_tail//""|tostring|length), stage_name, ci_run_dir, handler:(._handler//null)}'
