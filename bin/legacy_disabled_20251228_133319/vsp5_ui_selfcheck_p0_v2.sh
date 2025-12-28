#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${1:-http://127.0.0.1:8910}"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need curl; need jq; need sed; need awk

echo "== VSP5 UI SELFCHECK P0 (v2) =="
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
curl -sS "$BASE/api/vsp/runs?limit=1" | jq '{ok, run_id: .items[0].run_id, has: .items[0].has}'
echo

RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | jq -r '.items[0].run_id')"
echo "== (E) run_file new contract (rid/name) =="
for rel in "reports/index.html" "reports/run_gate_summary.json" "reports/findings_unified.json" "SUMMARY.txt"; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" "$BASE/api/vsp/run_file?rid=$RID&name=$rel" || true)"
  echo "rid/name $rel -> $code"
done
echo

echo "== (F) run_file legacy contract (run_id/path) =="
for rel in "reports/index.html" "reports/run_gate_summary.json" "reports/findings_unified.json" "SUMMARY.txt"; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" "$BASE/api/vsp/run_file?run_id=$RID&path=$rel" || true)"
  echo "run_id/path $rel -> $code"
done
echo

echo "== DONE =="
