#!/usr/bin/env bash
set -euo pipefail

UI="http://localhost:8910"
PROFILE="${1:-FULL_EXT}"
TARGET_TYPE="${2:-path}"
TARGET="${3:-/home/test/Data/SECURITY-10-10-v4}"

# --- Force KICS timeout via "multi-alias" envs (runner may read any one of these) ---
export VSP_TIMEOUT_KICS_SEC="${VSP_TIMEOUT_KICS_SEC:-15}"
export KICS_TIMEOUT_SEC="${KICS_TIMEOUT_SEC:-15}"
export VSP_KICS_TIMEOUT_SEC="${VSP_KICS_TIMEOUT_SEC:-15}"
export VSP_TOOL_TIMEOUT_SEC_KICS="${VSP_TOOL_TIMEOUT_SEC_KICS:-15}"

# Also keep other tools reasonable so we can see suite behavior
export VSP_TIMEOUT_SEMGREP_SEC="${VSP_TIMEOUT_SEMGREP_SEC:-1200}"
export VSP_TIMEOUT_CODEQL_SEC="${VSP_TIMEOUT_CODEQL_SEC:-1200}"
export VSP_TIMEOUT_TRIVY_SEC="${VSP_TIMEOUT_TRIVY_SEC:-1200}"
export VSP_TIMEOUT_SYFT_SEC="${VSP_TIMEOUT_SYFT_SEC:-1200}"
export VSP_TIMEOUT_GRIPE_SEC="${VSP_TIMEOUT_GRIPE_SEC:-1200}"

echo "[PROOF] UI=$UI"
echo "[PROOF] PROFILE=$PROFILE TARGET_TYPE=$TARGET_TYPE TARGET=$TARGET"
echo "[PROOF] Force KICS timeout ~ ${VSP_TIMEOUT_KICS_SEC}s"

RID="$(
  curl -fsS -X POST "$UI/api/vsp/run_v1" \
    -H "Content-Type: application/json" \
    -d "{\"mode\":\"local\",\"profile\":\"$PROFILE\",\"target_type\":\"$TARGET_TYPE\",\"target\":\"$TARGET\"}" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("request_id") or json.load(sys.stdin).get("rid") or "")'
)"

if [ -z "${RID:-}" ]; then
  echo "[ERR] Cannot get RID from /api/vsp/run_v1"
  exit 2
fi
echo "[PROOF] RID=$RID"

CI_DIR=""
for i in $(seq 1 240); do
  JS="$(curl -fsS "$UI/api/vsp/run_status_v1/$RID" || true)"
  CI_DIR="$(python3 - <<PY
import json,sys
try:
  d=json.loads(sys.argv[1])
  print(d.get("ci_run_dir","") or "")
except Exception:
  print("")
PY
"$JS")"
  STAGE="$(python3 - <<PY
import json,sys
try:
  d=json.loads(sys.argv[1])
  print(d.get("stage_sig","") or d.get("stage","") or "")
except Exception:
  print("")
PY
"$JS")"
  FINAL="$(python3 - <<PY
import json,sys
try:
  d=json.loads(sys.argv[1])
  print(str(d.get("final",False)))
except Exception:
  print("False")
PY
"$JS")"

  echo "[PROOF] poll#$i stage='$STAGE' ci_run_dir='$CI_DIR' final=$FINAL"

  if [ -n "$CI_DIR" ] && [ -d "$CI_DIR" ]; then
    break
  fi
  sleep 2
done

if [ -z "$CI_DIR" ] || [ ! -d "$CI_DIR" ]; then
  echo "[ERR] ci_run_dir not available/exists after polling."
  exit 3
fi

echo "[PROOF] CI_DIR=$CI_DIR"
echo "[PROOF] Watching KICS log & degraded_tools.json..."

KLOG="$CI_DIR/kics/kics.log"
DEG="$CI_DIR/degraded_tools.json"

for i in $(seq 1 240); do
  echo "---- tick#$i ----"
  if [ -f "$KLOG" ]; then
    echo "[KICS] last 6 lines:"
    tail -n 6 "$KLOG" | sed 's/\r/\n/g' || true
  else
    echo "[KICS] no kics.log yet: $KLOG"
  fi

  if [ -f "$DEG" ]; then
    echo "[DEGRADED] FOUND: $DEG"
    python3 - <<PY
import json,sys
p=sys.argv[1]
d=json.load(open(p,'r',encoding='utf-8',errors='ignore'))
print(json.dumps(d, indent=2, ensure_ascii=False))
PY
"$DEG"
    echo "[PROOF] OK: degraded_tools.json exists."
    exit 0
  else
    echo "[DEGRADED] not yet: $DEG"
  fi

  sleep 3
done

echo "[WARN] Timeout waiting degraded_tools.json (check runner stage progression)."
exit 4
