#!/usr/bin/env bash
set -euo pipefail

BASE="${BASE:-http://127.0.0.1:8910}"

echo "== [1] healthz =="
curl -fsS "$BASE/healthz" | jq .

echo "== [2] runs index =="
RID="$(curl -fsS "$BASE/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1" | jq -r '.items[0].run_id // empty')"
[ -n "$RID" ] || { echo "[ERR] cannot get RID"; exit 2; }
echo "[OK] RID=$RID"

echo "== [3] status v2 =="
curl -fsS "$BASE/api/vsp/run_status_v2/$RID" | jq '{ok,status,overall_verdict,ci,stage_name,stage_index,stage_total,has_kics:has("kics"), has_codeql:has("codeql"), has_gitleaks:has("gitleaks")}'

echo "== [4] artifacts index =="
curl -fsS -o /dev/null -w "HTTP=%{http_code}\n" "$BASE/api/vsp/run_artifacts_index_v1/$RID"

echo "== [5] findings preview =="
curl -fsS "$BASE/api/vsp/run_findings_preview_v1/$RID?limit=3" | jq '{ok,has_findings,total,warning,file,items_n:(.items|length)}'

echo "== [6] export probe headers =="
for fmt in html pdf zip; do
  echo "-- fmt=$fmt --"
  curl -sS -I "$BASE/api/vsp/run_export_v3/$RID?fmt=$fmt" | grep -iE "HTTP/|X-VSP-EXPORT-AVAILABLE" || true
done

echo "[DONE] selfcheck OK"
