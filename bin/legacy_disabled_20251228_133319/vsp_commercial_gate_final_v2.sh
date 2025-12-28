#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE:-http://127.0.0.1:8910}"
RID="${1:-}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "[FAIL] missing cmd: $1"; exit 2; }; }
need curl; need jq; need file; need head; need grep; need sed; need tr; need stat; need python3

if [ -z "${RID}" ]; then
  RAW="$(curl -fsS "${BASE}/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1" || true)"
  RID="$(echo "${RAW:-}" | jq -r '.items[0].run_id // empty' 2>/dev/null || true)"
  if [ -z "${RID}" ]; then
    echo "[FAIL] RID is empty"
    echo "[DEBUG] runs_index body:"
    echo "${RAW:-<empty>}" | head -c 800; echo
    exit 3
  fi
fi

echo "== VSP COMMERCIAL GATE FINAL V2 =="
echo "[BASE] ${BASE}"
echo "[RID ] ${RID}"

STATUS_JSON="$(curl -fsS "${BASE}/api/vsp/run_status_v2/${RID}")"
RUN_DIR="$(echo "$STATUS_JSON" | jq -r '.ci_run_dir // empty')"
[ -n "${RUN_DIR}" ] || { echo "[FAIL] status_v2 has no ci_run_dir"; echo "$STATUS_JSON" | jq .; exit 4; }
[ -d "${RUN_DIR}" ] || { echo "[FAIL] ci_run_dir not found on disk: ${RUN_DIR}"; exit 5; }
echo "[RUN_DIR] ${RUN_DIR}"

ok=1
fail() { ok=0; echo "[FAIL] $*"; }
pass() { echo "[OK] $*"; }
check_file() { local p="$1"; [ -f "$p" ] && [ "$(stat -c%s "$p" 2>/dev/null || echo 0)" -gt 10 ] && pass "file $p" || fail "missing/empty $p"; }

echo "== [1] tools artifacts =="
check_file "${RUN_DIR}/bandit/bandit.json"
check_file "${RUN_DIR}/semgrep/semgrep.json"
[ -f "${RUN_DIR}/gitleaks/gitleaks.json" ] && pass "file ${RUN_DIR}/gitleaks/gitleaks.json" || fail "missing ${RUN_DIR}/gitleaks/gitleaks.json"
check_file "${RUN_DIR}/kics/kics_summary.json"
check_file "${RUN_DIR}/trivy/trivy_summary.json"
check_file "${RUN_DIR}/syft/syft.json"
check_file "${RUN_DIR}/grype/grype.json"
ls "${RUN_DIR}/codeql"/* >/dev/null 2>&1 && pass "dir ${RUN_DIR}/codeql/* exists" || fail "missing codeql outputs under ${RUN_DIR}/codeql/"

echo "== [2] unify + severity normalization =="
check_file "${RUN_DIR}/findings_unified.json"
python3 - <<PY || { fail "severity normalization check failed"; }
import json,sys,os
p=os.path.join("${RUN_DIR}","findings_unified.json")
d=json.load(open(p,"r",encoding="utf-8"))
items=d.get("items") or []
allowed={"CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"}
bad=set()
for it in items[:200000]:
    s=(it.get("severity") or "TRACE").upper()
    if s not in allowed:
        bad.add(s)
if bad:
    print("BAD_SEVERITIES:",sorted(bad))
    sys.exit(2)
print("OK severity within 6-level; sampled=",min(len(items),200000),"total=",d.get("total"))
PY
pass "severity within 6-level"

echo "== [3] export v3 (REAL content-types) =="
PROBE="$(curl -fsS "${BASE}/api/vsp/run_export_v3/${RID}?probe=1" || true)"
echo "$PROBE" | jq -e '.ok==true' >/dev/null 2>&1 && pass "export probe ok=true" || fail "export probe not ok: $PROBE"

tmpd="$(mktemp -d)"; trap 'rm -rf "$tmpd"' EXIT
curl -fsS -D "${tmpd}/h.html.h" "${BASE}/api/vsp/run_export_v3/${RID}?fmt=html" -o "${tmpd}/out.html" || fail "download html failed"
grep -qi '^Content-Type: *text/html' "${tmpd}/h.html.h" && pass "html content-type" || fail "html wrong content-type"
head -n 1 "${tmpd}/out.html" | grep -qiE '^(<!doctype html|<html)' && pass "html looks real" || fail "html body not html"

curl -fsS -D "${tmpd}/h.zip.h" "${BASE}/api/vsp/run_export_v3/${RID}?fmt=zip" -o "${tmpd}/out.zip" || fail "download zip failed"
grep -qi '^Content-Type: *application/zip' "${tmpd}/h.zip.h" && pass "zip content-type" || fail "zip wrong content-type"
file "${tmpd}/out.zip" | grep -qi 'Zip archive' && pass "zip magic ok" || fail "zip file magic not zip"

curl -fsS -D "${tmpd}/h.pdf.h" "${BASE}/api/vsp/run_export_v3/${RID}?fmt=pdf" -o "${tmpd}/out.pdf" || fail "download pdf failed"
grep -qi '^Content-Type: *application/pdf' "${tmpd}/h.pdf.h" && pass "pdf content-type" || fail "pdf wrong content-type"
file "${tmpd}/out.pdf" | grep -qi 'PDF' && pass "pdf magic ok" || fail "pdf file magic not pdf"

echo "== [4] verdict =="
if [ "$ok" -eq 1 ]; then
  echo "COMMERCIAL_READY=YES"
  exit 0
else
  echo "COMMERCIAL_READY=NO"
  exit 10
fi
