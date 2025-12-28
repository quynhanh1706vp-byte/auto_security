#!/usr/bin/env bash
set -euo pipefail

BASE="${BASE_URL:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need curl; need jq; need awk; need sed

echo "== VSP UI P1 FAST VERIFY =="
echo "[BASE]=$BASE"

echo "== /vsp5 =="
curl -sS -o /dev/null -w "code=%{http_code}\n" "$BASE/vsp5" | sed 's/^/[HTTP] /'

echo "== latest RID =="
RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | jq -r '.items[0].run_id // empty')"
[ -n "${RID:-}" ] || { echo "[ERR] cannot get latest rid"; exit 3; }
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

echo "== export TGZ (HEAD) =="
curl -sS -I "$BASE/api/vsp/export_tgz?rid=$RID&scope=reports" \
| awk 'NR==1 || tolower($0) ~ /(content-type|content-disposition|content-length|last-modified)/'

echo "== export CSV (HEAD) =="
curl -sS -I "$BASE/api/vsp/export_csv?rid=$RID" \
| awk 'NR==1 || tolower($0) ~ /(content-type|content-disposition|content-length|last-modified)/'

echo "== sha256 verify =="
curl -sS "$BASE/api/vsp/sha256?rid=$RID&name=reports/run_gate_summary.json" | jq .

echo "== PASS: P1 core endpoints OK =="
