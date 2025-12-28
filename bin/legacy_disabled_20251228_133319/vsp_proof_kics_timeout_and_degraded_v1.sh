#!/usr/bin/env bash
set -euo pipefail

UI="http://localhost:8910"
PROFILE="${1:-FULL_EXT}"
TARGET_TYPE="${2:-path}"
TARGET="${3:-/home/test/Data/SECURITY-10-10-v4}"
T="${4:-15}"   # seconds

cd /home/test/Data/SECURITY_BUNDLE/ui

echo "[PROOF] UI=$UI"
echo "[PROOF] PROFILE=$PROFILE TARGET_TYPE=$TARGET_TYPE TARGET=$TARGET"
echo "[PROOF] FORCE KICS TIMEOUT = ${T}s (restart 8910 so CI inherits env)"

# ---- Force as many likely timeout knobs as possible ----
export VSP_TIMEOUT_KICS_SEC="$T"
export VSP_KICS_TIMEOUT_SEC="$T"
export KICS_TIMEOUT_SEC="$T"
export VSP_TOOL_TIMEOUT_SEC_KICS="$T"
export VSP_TOOL_TIMEOUT_KICS_SEC="$T"
export VSP_TIMEOUT_SEC_KICS="$T"

# defaults (in case runner uses a default fallback)
export VSP_TIMEOUT_SEC_DEFAULT="$T"
export VSP_TOOL_TIMEOUT_SEC_DEFAULT="$T"
export VSP_TIMEOUT_DEFAULT_SEC="$T"
export VSP_TOOL_TIMEOUT_DEFAULT_SEC="$T"

# some runners use generic names
export TOOL_TIMEOUT_SEC_DEFAULT="$T"
export TIMEOUT_SEC_DEFAULT="$T"
export TIMEOUT_SEC="$T"

echo "[PROOF] 1) Restart 8910 (clean) with current env..."
./bin/start_8910_clean_v2.sh >/dev/null 2>&1 || true

# wait a bit more robustly (curl race happens sometimes)
for i in {1..20}; do
  if curl -fsS "$UI/" >/dev/null 2>&1; then
    echo "[OK] 8910 reachable"
    break
  fi
  sleep 0.5
done

if ! curl -fsS "$UI/" >/dev/null 2>&1; then
  echo "[ERR] 8910 not reachable"
  echo "== ss :8910 =="; sudo ss -ltnp | grep ':8910' || true
  echo "== lsof :8910 =="; sudo lsof -nP -iTCP:8910 -sTCP:LISTEN || true
  tail -n 120 out_ci/ui_8910.log | sed 's/\r/\n/g' || true
  exit 2
fi

echo "[PROOF] 2) Trigger /api/vsp/run_v1 ..."
TMP="$(mktemp)"
HTTP="$(curl -sS -o "$TMP" -w "%{http_code}" -X POST "$UI/api/vsp/run_v1" \
  -H "Content-Type: application/json" \
  -d "{\"mode\":\"local\",\"profile\":\"$PROFILE\",\"target_type\":\"$TARGET_TYPE\",\"target\":\"$TARGET\"}")"

echo "[PROOF] run_v1 HTTP=$HTTP"
cat "$TMP"; echo
if [ "$HTTP" != "200" ]; then
  echo "[ERR] run_v1 failed"
  exit 3
fi

RID="$(python3 - <<PY
import json,sys
d=json.load(open("$TMP","r",encoding="utf-8"))
print(d.get("request_id") or d.get("req_id") or d.get("rid") or "")
PY
)"
if [ -z "$RID" ]; then
  echo "[ERR] Cannot extract RID from response"
  exit 4
fi
STATUS_URL="$UI/api/vsp/run_status_v1/$RID"
echo "[OK] RID=$RID"
echo "[OK] STATUS_URL=$STATUS_URL"

echo "[PROOF] 3) Wait for ci_run_dir to appear..."
CI_DIR=""
for i in {1..120}; do
  J="$(curl -sS "$STATUS_URL" || true)"
  CI_DIR="$(python3 - <<PY
import json,sys
try:
  d=json.loads("""$J""")
  print(d.get("ci_run_dir") or "")
except Exception:
  print("")
PY
)"
  if [ -n "$CI_DIR" ]; then
    echo "[OK] ci_run_dir=$CI_DIR"
    break
  fi
  sleep 1
done

if [ -z "$CI_DIR" ]; then
  echo "[ERR] ci_run_dir not found from status"
  echo "[DEBUG] status json:"
  curl -sS "$STATUS_URL" || true
  exit 5
fi

RUNNER_LOG="$CI_DIR/runner.log"
DEG="$CI_DIR/degraded_tools.json"
KICS_LOG="$CI_DIR/kics/kics.log"

echo "[PROOF] 4) Watch KICS timeout command line (expect '${T}s' in timeout wrapper)..."
FOUND_TIMEOUT_LINE=0
for i in {1..60}; do
  # show current timeout wrapper if present
  LINE="$(ps -ef | grep -E "timeout .*bin/run_kics_v2\.sh" | grep -v grep | head -n1 || true)"
  if [ -n "$LINE" ]; then
    echo "[PS] $LINE"
    if echo "$LINE" | grep -qE "timeout .* ${T}s "; then
      FOUND_TIMEOUT_LINE=1
      echo "[OK] timeout wrapper shows ${T}s"
      break
    fi
  fi
  sleep 1
done

if [ "$FOUND_TIMEOUT_LINE" -eq 0 ]; then
  echo "[WARN] Did not observe '${T}s' in ps line. We will still validate by outputs (degraded_tools + stage progression)."
fi

echo "[PROOF] 5) Wait up to ~$(($T+60))s for degrade evidence + stage progress..."
OK_DEG=0
OK_STAGE4=0

for i in $(seq 1 $(($T+60))); do
  # degraded_tools.json?
  if [ -f "$DEG" ]; then
    if grep -qiE '"kics"|kics' "$DEG"; then
      OK_DEG=1
    fi
  fi
  # stage after KICS?
  if [ -f "$RUNNER_LOG" ]; then
    if grep -qE "===== \[4/8\]|SEMGREP|Trivy|Syft|Grype|CODEQL" "$RUNNER_LOG"; then
      OK_STAGE4=1
    fi
  fi

  if [ "$OK_DEG" -eq 1 ] && [ "$OK_STAGE4" -eq 1 ]; then
    echo "[OK] degraded_tools contains KICS + runner moved past KICS"
    break
  fi
  sleep 1
done

echo
echo "================= PROOF SUMMARY ================="
echo "RID=$RID"
echo "CI_DIR=$CI_DIR"
echo "RUNNER_LOG=$RUNNER_LOG"
echo "DEGRADED_FILE=$DEG"
echo "KICS_LOG=$KICS_LOG"
echo "OK_DEGRADED_KICS=$OK_DEG"
echo "OK_STAGE_AFTER_KICS=$OK_STAGE4"
echo "================================================="

echo
echo "== tail runner.log =="
tail -n 120 "$RUNNER_LOG" 2>/dev/null | sed 's/\r/\n/g' || true

echo
echo "== degraded_tools.json =="
if [ -f "$DEG" ]; then
  cat "$DEG" | jq . 2>/dev/null || cat "$DEG"
else
  echo "MISSING: $DEG"
fi

echo
echo "== tail kics.log (if any) =="
tail -n 60 "$KICS_LOG" 2>/dev/null | sed 's/\r/\n/g' || true

# Exit non-zero if proof not satisfied
if [ "$OK_DEG" -ne 1 ] || [ "$OK_STAGE4" -ne 1 ]; then
  echo
  echo "[FAIL] Proof not satisfied yet."
  echo "Hints:"
  echo "  - If runner still uses 1800s, your runner reads a different env var; we will grep run_all_tools_v2.sh for the exact knob."
  echo "  - If KICS finishes quickly (no timeout), increase TARGET size or lower T (e.g. 5s) to force."
  exit 9
fi

echo "[PASS] KICS timeout/degrade proof OK + pipeline continued."
