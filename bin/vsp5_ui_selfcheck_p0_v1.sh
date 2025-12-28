#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${1:-http://127.0.0.1:8910}"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need curl; need jq; need sed; need awk; need python3

echo "== VSP5 UI SELFCHECK P0 =="
echo "[BASE] $BASE"
echo

echo "== (A) service listen =="
ss -lntp | grep -E '127\.0\.0\.1:8910' || echo "[WARN] not found in ss (maybe different bind)"
echo

echo "== (B) critical pages =="
for p in "/" "/vsp5" "/runs"; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" "$BASE$p" || true)"
  echo "GET $p -> $code"
done
echo

echo "== (C) critical APIs =="
for p in "/api/vsp/runs?limit=3" "/api/vsp/rule_overrides" "/api/vsp/settings"; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" "$BASE$p" || true)"
  echo "GET $p -> $code"
done
echo

echo "== (D) runs payload sanity (limit=1) =="
curl -sS "$BASE/api/vsp/runs?limit=1" | jq '{ok:(.items|type=="array"), run_id:(.items[0].run_id//null), has:(.items[0].has//null)}'
echo

echo "== (E) template & JS presence =="
TPL="templates/vsp_5tabs_enterprise_v2.html"
JS1="static/js/vsp_bundle_commercial_v2.js"
JS2="static/js/vsp_runs_tab_resolved_v1.js"

[ -f "$TPL" ] && echo "[OK] $TPL" || echo "[MISS] $TPL"
[ -f "$JS1" ] && echo "[OK] $JS1" || echo "[MISS] $JS1"
[ -f "$JS2" ] && echo "[OK] $JS2" || echo "[MISS] $JS2"
echo

echo "== (F) node --check JS (if node exists) =="
if command -v node >/dev/null 2>&1; then
  for f in "$JS1" "$JS2"; do
    [ -f "$f" ] || continue
    node --check "$f" && echo "[OK] node --check: $f" || { echo "[ERR] node --check fail: $f"; exit 3; }
  done
else
  echo "[SKIP] node missing"
fi
echo

echo "== (G) spot-check run_file compat (try latest run) =="
RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | jq -r '.items[0].run_id // empty')"
if [ -n "${RID:-}" ]; then
  # Try common report targets via legacy compat endpoint
  for rel in "reports/index.html" "reports/run_gate_summary.json" "findings_unified.json" "SUMMARY.txt"; do
    code="$(curl -sS -o /dev/null -w "%{http_code}" "$BASE/api/vsp/run_file?run_id=$RID&path=$rel" || true)"
    echo "run_file?run_id=$RID&path=$rel -> $code"
  done
else
  echo "[WARN] cannot derive latest run_id"
fi

echo
echo "== DONE =="
