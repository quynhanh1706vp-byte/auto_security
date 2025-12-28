#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need curl; need jq; need tar; need sha256sum; need mktemp; need date

API_BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${1:-}"

# Pick latest RID if not provided
if [ -z "$RID" ]; then
  RID="$(curl -fsS "${API_BASE}/api/vsp/runs?limit=1" | jq -r '.items[0].run_id // empty')"
fi
[ -n "$RID" ] || { echo "[ERR] cannot determine RID"; exit 2; }

echo "[INFO] API_BASE=${API_BASE}"
echo "[INFO] RID=${RID}"

echo "== (A) 3-click demo + sha verify =="
VSP_UI_BASE="${API_BASE}" bin/p1_demo_3click_by_rid_v1.sh "${RID}"

echo "== (B) Export bundle by RID =="
VSP_UI_BASE="${API_BASE}" bin/p1_export_bundle_by_rid_v1.sh "${RID}"

# Find newest bundle for this RID
BUNDLE="$(ls -1t out_ci/bundles/"${RID}".bundle.*.tgz 2>/dev/null | head -n1 || true)"
[ -n "${BUNDLE}" ] || { echo "[FAIL] bundle not found for RID=${RID}"; exit 3; }

echo "[INFO] BUNDLE=${BUNDLE}"

echo "== (C) Inspect bundle top =="
tar -tzf "${BUNDLE}" | sed -n '1,40p'

echo "== (D) Verify BUNDLE_SHA256SUMS inside bundle =="
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
tar -xzf "${BUNDLE}" -C "${TMP}"
( cd "${TMP}" && sha256sum -c BUNDLE_SHA256SUMS.txt ) | tail -n 50

echo "== RESULT =="
echo "PASS (RID=${RID})"
echo "BUNDLE=${BUNDLE}"
