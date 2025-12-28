#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE:-http://127.0.0.1:8910}"
echo "== VSP UI 5-TABS SMOKE P2 =="
echo "[BASE]=$BASE"

# 1) endpoints
URLS=(
  "$BASE/vsp4"
  "$BASE/api/vsp/latest_rid_v1"
  "$BASE/api/vsp/runs_index_v3_fs_resolved?limit=3"
  "$BASE/api/vsp/findings_latest_v1?limit=3"
  "$BASE/api/vsp/rule_overrides_v1"
  "$BASE/api/vsp/dashboard_commercial_v2"
  "$BASE/static/js/vsp_bundle_commercial_v2.js"
)
fails=0
for u in "${URLS[@]}"; do
  c="$(curl -sS -m 4 -o /dev/null -w '%{http_code}' "$u" || echo 000)"
  printf "[HTTP] %s %s\n" "$c" "$u"
  [ "$c" = "200" ] || fails=$((fails+1))
done

# 2) 5 tabs routes (hash) – just ensure HTML served
for h in dashboard runs datasource settings rules; do
  c="$(curl -sS -m 4 -o /dev/null -w '%{http_code}' "$BASE/vsp4#$h" || echo 000)"
  printf "[TAB]  %s /vsp4#%s\n" "$c" "$h"
  [ "$c" = "200" ] || fails=$((fails+1))
done

echo "== RESULT =="
if [ "$fails" -eq 0 ]; then
  echo "[OK] all green"
else
  echo "[FAIL] fails=$fails"
  exit 2
fi
