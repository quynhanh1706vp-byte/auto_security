#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need curl; need jq; need sha256sum; need mktemp; need date

API_BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${1:-}"
NAME="${2:-reports/run_gate_summary.json}"

if [ -z "${RID}" ]; then
  RID="$(curl -fsS "${API_BASE}/api/vsp/runs?limit=1" | jq -r '.items[0].run_id // empty')"
fi
[ -n "${RID}" ] || { echo "[ERR] cannot determine RID"; exit 2; }

echo "[INFO] API_BASE=${API_BASE}"
echo "[INFO] RID=${RID}"

fail(){ echo "[FAIL] $*"; exit 3; }
ok(){ echo "[OK] $*"; }

echo "== (1) HEAD TGZ reports =="
H1="$(curl -fsSI "${API_BASE}/api/vsp/export_tgz?rid=${RID}&scope=reports" || true)"
echo "$H1" | grep -qi '^HTTP/.* 200' || fail "export_tgz not 200"
echo "$H1" | grep -qi 'Content-Disposition:.*attachment' || fail "export_tgz missing Content-Disposition"
ok "export_tgz HEAD 200 + Content-Disposition"

echo "== (2) HEAD CSV =="
H2="$(curl -fsSI "${API_BASE}/api/vsp/export_csv?rid=${RID}" || true)"
echo "$H2" | grep -qi '^HTTP/.* 200' || fail "export_csv not 200"
echo "$H2" | grep -qi 'Content-Disposition:.*attachment' || fail "export_csv missing Content-Disposition"
ok "export_csv HEAD 200 + Content-Disposition"

echo "== (3) SHA verify (remote vs local) =="
REMOTE="$(curl -fsS "${API_BASE}/api/vsp/sha256?rid=${RID}&name=$(python3 - <<PY
import urllib.parse
print(urllib.parse.quote("${NAME}", safe=""))
PY
)" | jq -r '.sha256 // .hash // empty')"
[ -n "${REMOTE}" ] || fail "sha256 endpoint returned empty hash"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsS -L "${API_BASE}/api/vsp/run_file?rid=${RID}&name=$(python3 - <<PY
import urllib.parse
print(urllib.parse.quote("${NAME}", safe=""))
PY
)" -o "${TMP}/file"

LOCAL="$(sha256sum "${TMP}/file" | awk '{print $1}')"
[ "${LOCAL}" = "${REMOTE}" ] || fail "sha mismatch: local=${LOCAL} remote=${REMOTE}"
ok "sha match OK (${NAME})"

echo "== RESULT =="
echo "PASS (RID=${RID})"
