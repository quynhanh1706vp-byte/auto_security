#!/usr/bin/env bash
set -euo pipefail
BASE="http://localhost:8910"

REQ_JSON="$(curl -sS -X POST "$BASE/api/vsp/run_v1" -H "Content-Type: application/json" \
  -d '{"mode":"local","profile":"FULL_EXT","target_type":"path","target":"/home/test/Data/SECURITY-10-10-v4"}')"

REQ_ID="$(python3 - <<PY
import json
o=json.loads('''$REQ_JSON''')
print(o.get("request_id") or o.get("req_id") or o.get("requestId") or o.get("id") or "")
PY
)"

if [ -z "$REQ_ID" ]; then
  echo "[ERR] cannot get request_id. Response was:"
  echo "$REQ_JSON"
  exit 2
fi

echo "[OK] REQ_ID=$REQ_ID"

for t in $(seq 1 30); do
  S="$(curl -sS "$BASE/api/vsp/run_status_v1/$REQ_ID")"
  python3 - <<PY
import json
o=json.loads('''$S''')
keys=["status","final","killed","kill_reason","stall_timeout_sec","total_timeout_sec","progress_pct","stage_index","stage_total","stage_name","stage_sig"]
print({k:o.get(k) for k in keys})
PY
  FIN="$(python3 - <<PY
import json
o=json.loads('''$S''')
print("1" if o.get("final") else "0")
PY
)"
  if [ "$FIN" = "1" ]; then
    echo "== FINAL reached at t=$t =="
    break
  fi
  sleep 1
done
