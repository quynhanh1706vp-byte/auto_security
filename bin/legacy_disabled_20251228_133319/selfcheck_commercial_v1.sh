#!/usr/bin/env bash
set -euo pipefail

BASE="http://127.0.0.1:8910"
TIMEOUT_SEC="${TIMEOUT_SEC:-900}"
SLEEP_SEC="${SLEEP_SEC:-5}"

echo "== [1] runs_index_v3_fs =="
curl -sS "$BASE/api/vsp/runs_index_v3_fs?limit=1&hide_empty=0" | jq '{ok, n:(.items|length), first:(.items[0].run_id//null)}'

echo "== [2] trigger run_v1 =="
RSP="$(curl -sS -X POST "$BASE/api/vsp/run_v1" -H 'Content-Type: application/json' -d '{}')"
echo "$RSP" | jq .
RID="$(echo "$RSP" | jq -r '.request_id // .req_id // empty')"
[ -n "$RID" ] || { echo "[ERR] missing request_id"; exit 2; }
echo "[OK] RID=$RID"

deadline=$((SECONDS+TIMEOUT_SEC))
while [ $SECONDS -lt $deadline ]; do
  J="$(curl -sS "$BASE/api/vsp/run_status_v2/$RID")"
  ok="$(echo "$J" | jq -r '.ok // false')"
  ci="$(echo "$J" | jq -r '.ci_run_dir // empty')"
  pct="$(echo "$J" | jq -r '.progress_pct // 0')"
  stage_i="$(echo "$J" | jq -r '.stage_index // 0')"
  stage_t="$(echo "$J" | jq -r '.stage_total // 0')"
  kv="$(echo "$J" | jq -r '.kics_verdict // ""')"
  kt="$(echo "$J" | jq -r '.kics_total // 0')"

  echo "[POLL] ok=$ok pct=$pct stage=$stage_i/$stage_t ci=${ci:-none} kics=($kv,$kt)"

  # Contract asserts (must always hold)
  echo "$J" | jq -e 'has("ok") and has("ci_run_dir") and has("stage_index") and has("stage_total") and has("progress_pct") and has("degraded_tools")' >/dev/null

  # If KICS summary exists, we’re good for the KICS lane
  if [ -n "$ci" ] && [ -f "$ci/kics/kics_summary.json" ]; then
    echo "[OK] kics_summary.json exists"
    cat "$ci/kics/kics_summary.json" | jq '{tool,verdict,total,counts}'
    exit 0
  fi

  sleep "$SLEEP_SEC"
done

echo "[ERR] timeout waiting for kics_summary.json"
exit 3
