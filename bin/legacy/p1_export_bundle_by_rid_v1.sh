#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need curl; need jq; need tar; need sha256sum; need date; need mktemp; need sed

API_BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${1:-}"

if [ -z "${RID}" ]; then
  RID="$(curl -fsS "${API_BASE}/api/vsp/runs?limit=1" | jq -r '.items[0].run_id // empty')"
fi
[ -n "${RID}" ] || { echo "[ERR] cannot determine RID"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="$(pwd)/out_ci/bundles"
mkdir -p "${OUT_DIR}"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

echo "[INFO] API_BASE=${API_BASE}"
echo "[INFO] RID=${RID}"
echo "[INFO] WORK=${WORK}"

# Required files (must exist)
REQ_FILES=(
  "reports/index.html"
  "reports/run_gate_summary.json"
  "reports/findings_unified.json"
  "reports/SUMMARY.txt"
  "reports/SHA256SUMS.txt"
)

# Optional extras (best effort)
OPT_FILES=(
  "reports/findings_unified.csv"
  "reports/findings_unified.sarif"
  "reports/findings_unified.sarif.json"
  "reports/findings_unified.sarif.gz"
)

fetch_run_file(){
  local name="$1"
  local dst="${WORK}/${name}"
  mkdir -p "$(dirname "$dst")"
  # Follow 302 if gateway redirects to /api/vsp/run_file...
  if curl -fsS -L "${API_BASE}/api/vsp/run_file?rid=${RID}&name=$(python3 - <<PY
import urllib.parse
print(urllib.parse.quote("${name}", safe=""))
PY
)" -o "${dst}"; then
    echo "[OK] fetched: ${name}"
    return 0
  else
    return 1
  fi
}

echo "== (1) Fetch REQUIRED files =="
for f in "${REQ_FILES[@]}"; do
  if ! fetch_run_file "$f"; then
    echo "[FAIL] missing required file: $f"
    exit 3
  fi
done

echo "== (2) Fetch OPTIONAL files (ignore if missing) =="
for f in "${OPT_FILES[@]}"; do
  if fetch_run_file "$f"; then :; else echo "[SKIP] optional missing: $f"; fi
done

# Also try to fetch CSV via export endpoint (best effort) into reports/findings_unified.csv if not already present
if [ ! -s "${WORK}/reports/findings_unified.csv" ]; then
  if curl -fsS -L "${API_BASE}/api/vsp/export_csv?rid=${RID}" -o "${WORK}/reports/findings_unified.csv"; then
    echo "[OK] fetched via export_csv -> reports/findings_unified.csv"
  else
    rm -f "${WORK}/reports/findings_unified.csv" 2>/dev/null || true
    echo "[SKIP] export_csv not available"
  fi
fi

# Manifest
cat > "${WORK}/bundle_manifest.json" <<JSON
{
  "schema_version": "1.0",
  "rid": "$(printf "%s" "$RID" | sed 's/"/\\"/g')",
  "created_at": "${TS}",
  "api_base": "$(printf "%s" "$API_BASE" | sed 's/"/\\"/g')",
  "notes": "Commercial bundle by RID. REQUIRED: reports/index.html, run_gate_summary.json, findings_unified.json, SUMMARY.txt, SHA256SUMS.txt. OPTIONAL: findings_unified.csv/sarif."
}
JSON

# Bundle sha list (for what we pack)
(
  cd "${WORK}"
  # Stable-ish ordering
  find . -type f ! -name 'BUNDLE_SHA256SUMS.txt' -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum
) > "${WORK}/BUNDLE_SHA256SUMS.txt"

BUNDLE="${OUT_DIR}/${RID}.bundle.${TS}.tgz"
(
  cd "${WORK}"
  # Pack relative paths without leading ./
  tar -czf "${BUNDLE}" \
    bundle_manifest.json BUNDLE_SHA256SUMS.txt reports
)

echo "[DONE] bundle: ${BUNDLE}"
echo "[HINT] verify: tar -tzf ${BUNDLE} | head"
echo "[HINT] sha:    (cd ${OUT_DIR} && sha256sum $(basename "${BUNDLE}"))"
