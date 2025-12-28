#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/COMMERCIAL_EVIDENCE_${TS}"
mkdir -p "$OUT"

BASE="http://127.0.0.1:8910"
echo "== COMMERCIAL GATE P2 ==" | tee "$OUT/gate.log"
echo "[BASE]=$BASE" | tee -a "$OUT/gate.log"

echo "== 1) endpoints 200 ==" | tee -a "$OUT/gate.log"
URLS=(
  "$BASE/vsp4"
  "$BASE/static/js/vsp_bundle_commercial_v2.js"
  "$BASE/api/vsp/latest_rid_v1"
  "$BASE/api/vsp/dashboard_commercial_v1"
  "$BASE/api/vsp/findings_latest_v1?limit=3"
  "$BASE/api/vsp/runs_index_v3_fs_resolved?limit=1"
  "$BASE/api/vsp/rule_overrides_v1"
)
for u in "${URLS[@]}"; do
  code="$(curl -sS -m 4 -o /dev/null -w '%{http_code}' "$u" || echo 000)"
  echo "[HTTP] $code $u" | tee -a "$OUT/gate.log"
done

echo "== 2) latest run_dir + verify/export ==" | tee -a "$OUT/gate.log"
J="$(curl -sS $BASE/api/vsp/latest_rid_v1 || true)"
echo "$J" > "$OUT/latest_rid_v1.json"
RD="$(echo "$J" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("ci_run_dir",""))' 2>/dev/null || true)"
echo "[RUN_DIR]=$RD" | tee -a "$OUT/gate.log"

if [ -n "${RD:-}" ]; then
  QRD="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$RD")"
  curl -sS "$BASE/api/vsp/verify_report_sha_v1?run_dir=$QRD" | tee "$OUT/verify_sha.json" | head -c 400 >/dev/null || true
  curl -sS -I "$BASE/api/vsp/export_report_tgz_v1?run_dir=$QRD" | tee "$OUT/export_head.txt" | head -n 20 >/dev/null || true
fi

echo "== 3) stability 10min (no non-200) ==" | tee -a "$OUT/gate.log"
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_stability_smoke_p0_v1.sh 600 | tee "$OUT/stability_10min.log" || true

echo "== 4) log scan (no traceback/500) ==" | tee -a "$OUT/gate.log"
ERR="out_ci/ui_8910.error.log"
ACC="out_ci/ui_8910.access.log"
cp -f "$ERR" "$OUT/ui_8910.error.log" 2>/dev/null || true
cp -f "$ACC" "$OUT/ui_8910.access.log" 2>/dev/null || true
grep -nE "Traceback|Exception|ERROR|HTTP_500|500 " "$OUT/ui_8910.error.log" | head -n 80 > "$OUT/error_scan.txt" || true

echo "== 5) pack evidence ==" | tee -a "$OUT/gate.log"
tar -czf "out_ci/COMMERCIAL_EVIDENCE_${TS}.tgz" -C out_ci "COMMERCIAL_EVIDENCE_${TS}"
( cd out_ci && sha256sum "COMMERCIAL_EVIDENCE_${TS}.tgz" > "COMMERCIAL_EVIDENCE_${TS}.SHA256SUMS.txt" )
echo "[OK] out_ci/COMMERCIAL_EVIDENCE_${TS}.tgz" | tee -a "$OUT/gate.log"
echo "[OK] out_ci/COMMERCIAL_EVIDENCE_${TS}.SHA256SUMS.txt" | tee -a "$OUT/gate.log"
