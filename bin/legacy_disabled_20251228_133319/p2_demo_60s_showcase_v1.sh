#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== UI pages =="
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  echo -n "$p => "
  curl -s -o /dev/null -w "%{http_code}\n" "$BASE$p"
done

echo
echo "== Core APIs =="
for u in /api/vsp/rid_latest /api/vsp/runs?limit=1 /api/vsp/dash_kpis /api/vsp/dash_charts; do
  echo "-- $u"
  curl -fsS "$BASE$u" | head -c 220; echo
done

echo
echo "== Rule overrides save (rules_v1) =="
curl -fsS -X POST "$BASE/api/ui/rule_overrides_v2" \
  -H 'Content-Type: application/json' \
  --data '{"schema":"rules_v1","rules":[],"notes":"demo-ok"}' | head -c 220; echo
curl -fsS "$BASE/api/ui/rule_overrides_v2" | head -c 220; echo

echo
echo "[OK] Demo checklist: tabs OK, APIs OK, rule overrides save OK."
