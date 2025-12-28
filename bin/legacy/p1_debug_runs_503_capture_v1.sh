#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE:-http://127.0.0.1:8910}"

echo "== server-side probe 30x /api/vsp/runs?limit=1 =="
fail=0
for i in $(seq 1 30); do
  code="$(curl -sS -o /tmp/r.json -w '%{http_code}' "$BASE/api/vsp/runs?limit=1" || true)"
  ok="$(jq -r '.ok // empty' /tmp/r.json 2>/dev/null || true)"
  rid="$(jq -r '.rid_latest // empty' /tmp/r.json 2>/dev/null || true)"
  printf "%02d) http=%s ok=%s rid=%s\n" "$i" "$code" "$ok" "$rid"
  [[ "$code" == "200" ]] || fail=$((fail+1))
  sleep 0.2
done
echo "fail_count=$fail"

echo
echo "== tail error log =="
tail -n 160 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log 2>/dev/null || true
