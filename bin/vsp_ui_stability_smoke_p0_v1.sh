#!/usr/bin/env bash
set -euo pipefail

BASE="http://127.0.0.1:8910"
N="${1:-60}"

echo "== VSP UI STABILITY SMOKE P0 =="
echo "[BASE]=$BASE [N]=$N"

fails=0
for i in $(seq 1 "$N"); do
  for u in \
    "$BASE/vsp4" \
    "$BASE/api/vsp/latest_rid_v1" \
    "$BASE/api/vsp/dashboard_v3" \
    "$BASE/api/vsp/runs_index_v3_fs_resolved?limit=1" \
    "$BASE/static/js/vsp_bundle_commercial_v2.js" \
  ; do
    code="$(curl -sS -m 4 -o /dev/null -w '%{http_code}' "$u" || echo 000)"
    if [ "$code" != "200" ]; then
      echo "[FAIL] i=$i code=$code url=$u"
      fails=$((fails+1))
    fi
  done
  sleep 1
done

echo "== RESULT =="
if [ "$fails" -eq 0 ]; then
  echo "[OK] stable: no non-200 in $N rounds"
else
  echo "[WARN] fails=$fails (check out_ci/ui_8910.error.log)"
fi
