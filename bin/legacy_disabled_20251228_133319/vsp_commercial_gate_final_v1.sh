#!/usr/bin/env bash
set -euo pipefail

BASE="${BASE:-http://127.0.0.1:8910}"
RID="${1:-}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "[FAIL] missing cmd: $1"; exit 2; }; }
need curl; need jq; need file; need head; need grep; need sed; need tr

# pick latest if not provided
if [ -z "${RID}" ]; then
  RID="$(curl -fsS "${BASE}/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1" | jq -r '.items[0].run_id // empty')"
fi
[ -n "${RID}" ] || { echo "[FAIL] RID is empty"; exit 3; }

echo "== VSP COMMERCIAL GATE FINAL =="
echo "[BASE] ${BASE}"
echo "[RID ] ${RID}"

# resolve run_dir from status_v2
STATUS_JSON="$(curl -fsS "${BASE}/api/vsp/run_status_v2/${RID}")"
RUN_DIR="$(echo "$STATUS_JSON" | jq -r '.ci_run_dir // empty')"
[ -n "${RUN_DIR}" ] || { echo "[FAIL] status_v2 has no ci_run_dir"; echo "$STATUS_JSON" | jq .; exit 4; }
[ -d "${RUN_DIR}" ] || { echo "[FAIL] ci_run_dir not found on disk: ${RUN_DIR}"; exit 5; }
echo "[RUN_DIR] ${RUN_DIR}"

ok=1
fail() { ok=0; echo "[FAIL] $*"; }
pass() { echo "[OK] $*"; }

# --- tool artifacts quick checks (commercial expectations)
check_file() { local p="$1"; [ -f "$p" ] && [ "$(stat -c%s "$p" 2>/dev/null || echo 0)" -gt 10 ] && pass "file $p" || fail "missing/empty $p"; }

echo "== [1] tools artifacts =="
check_file "${RUN_DIR}/bandit/bandit.json"
check_file "${RUN_DIR}/semgrep/semgrep.json"

# gitleaks may be json or report
if [ -f "${RUN_DIR}/gitleaks/gitleaks.json" ]; then pass "file ${RUN_DIR}/gitleaks/gitleaks.json"; else fail "missing ${RUN_DIR}/gitleaks/gitleaks.json"; fi

check_file "${RUN_DIR}/kics/kics_summary.json"
check_file "${RUN_DIR}/trivy/trivy_summary.json"
check_file "${RUN_DIR}/syft/syft.json"
check_file "${RUN_DIR}/grype/grype.json"

# codeql can vary; accept summary or sarif
if ls "${RUN_DIR}/codeql"/* >/dev/null 2>&1; then
  pass "dir ${RUN_DIR}/codeql/* exists"
else
  fail "missing codeql outputs under ${RUN_DIR}/codeql/"
fi

echo "== [2] unify + severity normalization =="
check_file "${RUN_DIR}/findings_unified.json"
# verify severity set is exactly within 6-level (allow missing ones if zero)
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
RIDN="$(echo "$RID" | sed 's/^RUN_//')"

# probe must be ok=true
PROBE="$(curl -fsS "${BASE}/api/vsp/run_export_v3/${RID}?probe=1")" || { fail "export probe request failed"; PROBE=""; }
if echo "$PROBE" | jq -e '.ok==true' >/dev/null 2>&1; then
  pass "export probe ok=true"
else
  fail "export probe not ok: $PROBE"
fi

tmpd="$(mktemp -d)"
trap 'rm -rf "$tmpd"' EXIT

# html
curl -fsS -D "${tmpd}/h.html.h" "${BASE}/api/vsp/run_export_v3/${RID}?fmt=html" -o "${tmpd}/out.html" || fail "download html failed"
grep -qi '^Content-Type: *text/html' "${tmpd}/h.html.h" && pass "html content-type" || fail "html wrong content-type"
head -n 1 "${tmpd}/out.html" | grep -qiE '^(<!doctype html|<html)' && pass "html looks real" || fail "html body not html"

# zip
curl -fsS -D "${tmpd}/h.zip.h" "${BASE}/api/vsp/run_export_v3/${RID}?fmt=zip" -o "${tmpd}/out.zip" || fail "download zip failed"
grep -qi '^Content-Type: *application/zip' "${tmpd}/h.zip.h" && pass "zip content-type" || fail "zip wrong content-type"
file "${tmpd}/out.zip" | grep -qi 'Zip archive' && pass "zip magic ok" || fail "zip file magic not zip"

# pdf
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
