#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need curl; need jq; need date; need sha256sum; need mkdir; need ls

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | jq -r '.items[0].run_id')"
[ -n "$RID" ] && [ "$RID" != "null" ] || { echo "[ERR] cannot get RID"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/BOSS_BUNDLE_${RID}_${TS}"
mkdir -p "$OUT"
echo "[INFO] BASE=$BASE"
echo "[INFO] RID=$RID"
echo "[INFO] OUT=$OUT"

# Download main artifacts
curl -fsSL "$BASE/api/vsp/export_tgz?rid=${RID}&scope=reports" -o "$OUT/${RID}.reports.tgz"
curl -fsSL "$BASE/api/vsp/export_csv?rid=${RID}" -o "$OUT/${RID}.findings.csv"

# Download key JSON/TXT files via run_file paths if available
curl -fsSL "$BASE/api/vsp/run_file?rid=${RID}&name=reports%2Frun_gate_summary.json" -o "$OUT/run_gate_summary.json" || true
curl -fsSL "$BASE/api/vsp/run_file?rid=${RID}&name=reports%2Ffindings_unified.json" -o "$OUT/findings_unified.json" || true
curl -fsSL "$BASE/api/vsp/run_file?rid=${RID}&name=reports%2FSUMMARY.txt" -o "$OUT/SUMMARY.txt" || true
curl -fsSL "$BASE/api/vsp/run_file?rid=${RID}&name=reports%2FSHA256SUMS.txt" -o "$OUT/SHA256SUMS.txt" || true

# Add a small README with “how to open”
cat > "$OUT/README.txt" <<EOF
VSP Commercial Bundle
BASE: $BASE
RID : $RID

Open report (online):
  $BASE/api/vsp/run_file?rid=$RID&name=reports%2Findex.html

Downloaded files:
  - ${RID}.reports.tgz
  - ${RID}.findings.csv
  - run_gate_summary.json (if present)
  - findings_unified.json (if present)
  - SUMMARY.txt (if present)
  - SHA256SUMS.txt (if present)
EOF

# Local checksum for what we downloaded
( cd "$OUT" && sha256sum * > LOCAL_SHA256SUMS.txt )

echo "[OK] wrote bundle folder: $OUT"
ls -la "$OUT" | sed -n '1,200p'
echo "[OPEN] $BASE/api/vsp/run_file?rid=$RID&name=reports%2Findex.html"
