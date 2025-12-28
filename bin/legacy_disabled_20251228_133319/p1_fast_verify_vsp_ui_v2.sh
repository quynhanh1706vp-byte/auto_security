#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE_URL:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need curl; need jq; need awk; need sed

echo "== VSP UI P1 FAST VERIFY V2 (with retry) =="
echo "[BASE]=$BASE"

echo "== /vsp5 =="
curl -sS -o /dev/null -w "code=%{http_code}\n" "$BASE/vsp5" | sed 's/^/[HTTP] /'

echo "== wait /api/vsp/runs returns JSON =="
RID=""
for i in $(seq 1 30); do
  raw="$(curl -sS "$BASE/api/vsp/runs?limit=1" || true)"
  if echo "$raw" | jq -e '.items[0].run_id' >/dev/null 2>&1; then
    RID="$(echo "$raw" | jq -r '.items[0].run_id')"
    break
  fi
  sleep 0.3
done
[ -n "${RID:-}" ] || {
  echo "[ERR] /api/vsp/runs not JSON yet. First 200 chars:"
  curl -sS "$BASE/api/vsp/runs?limit=1" | head -c 200; echo
  exit 3
}

echo "RID=$RID"

echo "== required reports via run_file HEAD (must be 200) =="
for f in \
  reports/index.html \
  reports/run_gate_summary.json \
  reports/findings_unified.json \
  reports/SUMMARY.txt \
  reports/SHA256SUMS.txt
do
  code="$(curl -sS -I "$BASE/api/vsp/run_file?rid=$RID&name=$f" | awk 'NR==1{print $2}')"
  echo "$f -> $code"
  [ "$code" = "200" ] || { echo "[FAIL] missing/blocked: $f"; exit 4; }
done

echo "== PASS: P1 core endpoints OK =="
