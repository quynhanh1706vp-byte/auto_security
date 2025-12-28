#!/usr/bin/env bash
set -euo pipefail

UI="http://localhost:8910"
PROFILE="${1:-FULL_EXT}"
TARGET_TYPE="${2:-path}"
TARGET="${3:-/home/test/Data/SECURITY-10-10-v4}"

# force KICS timeout via multi-alias envs
export VSP_TIMEOUT_KICS_SEC="${VSP_TIMEOUT_KICS_SEC:-15}"
export KICS_TIMEOUT_SEC="${KICS_TIMEOUT_SEC:-15}"
export VSP_KICS_TIMEOUT_SEC="${VSP_KICS_TIMEOUT_SEC:-15}"
export VSP_TOOL_TIMEOUT_SEC_KICS="${VSP_TOOL_TIMEOUT_SEC_KICS:-15}"

echo "[PROOF] UI=$UI"
echo "[PROOF] PROFILE=$PROFILE TARGET_TYPE=$TARGET_TYPE TARGET=$TARGET"
echo "[PROOF] Force KICS timeout ~ ${VSP_TIMEOUT_KICS_SEC}s"

TMP="$(mktemp)"
HTTP="$(curl -sS -o "$TMP" -w "%{http_code}" -X POST "$UI/api/vsp/run_v1" \
  -H "Content-Type: application/json" \
  -d "{\"mode\":\"local\",\"profile\":\"$PROFILE\",\"target_type\":\"$TARGET_TYPE\",\"target\":\"$TARGET\"}" || true)"

BODY="$(cat "$TMP" 2>/dev/null || true)"
rm -f "$TMP"

echo "[PROOF] /api/vsp/run_v1 HTTP=$HTTP"
if [ "$HTTP" != "200" ]; then
  echo "[ERR] run_v1 not 200. Body head:"
  echo "$BODY" | head -n 60
  exit 2
fi

# Must be JSON object
if ! echo "$BODY" | head -c 1 | grep -q '{'; then
  echo "[ERR] run_v1 did not return JSON. Body head:"
  echo "$BODY" | head -n 60
  exit 3
fi

RID="$(echo "$BODY" | jq -r '.req_id // .request_id // .rid // empty' 2>/dev/null || true)"
if [ -z "${RID:-}" ]; then
  echo "[ERR] Cannot extract RID. Full JSON:"
  echo "$BODY"
  exit 4
fi
echo "[PROOF] RID=$RID"

CI_DIR=""
for i in $(seq 1 300); do
  JS="$(curl -fsS "$UI/api/vsp/run_status_v1/$RID" || true)"
  CI_DIR="$(echo "$JS" | jq -r '.ci_run_dir // .ci_dir // empty' 2>/dev/null || true)"
  STAGE="$(echo "$JS" | jq -r '.stage_sig // .stage // empty' 2>/dev/null || true)"
  FINAL="$(echo "$JS" | jq -r '.final // false' 2>/dev/null || echo "false")"
  REASON="$(echo "$JS" | jq -r '.finish_reason // empty' 2>/dev/null || true)"
  PROG="$(echo "$JS" | jq -r '.progress_pct // 0' 2>/dev/null || echo "0")"
  echo "[PROOF] poll#$i stage='$STAGE' reason='$REASON' progress=$PROG ci_run_dir='$CI_DIR' final=$FINAL"
  if [ -n "$CI_DIR" ] && [ -d "$CI_DIR" ]; then
    break
  fi
  sleep 2
done

if [ -z "$CI_DIR" ] || [ ! -d "$CI_DIR" ]; then
  echo "[ERR] ci_run_dir not available/exists after polling."
  echo "[HINT] Check UI log: tail -n 200 out_ci/ui_8910.log"
  exit 5
fi

echo "[PROOF] CI_DIR=$CI_DIR"
KLOG="$CI_DIR/kics/kics.log"
DEG="$CI_DIR/degraded_tools.json"

for i in $(seq 1 360); do
  echo "---- tick#$i ----"
  if [ -f "$KLOG" ]; then
    echo "[KICS] last 12 lines:"
    tail -n 12 "$KLOG" | sed 's/\r/\n/g' || true
  else
    echo "[KICS] no kics.log yet: $KLOG"
  fi

  if [ -f "$DEG" ]; then
    echo "[DEGRADED] FOUND: $DEG"
    jq . "$DEG" || cat "$DEG"
    exit 0
  else
    echo "[DEGRADED] not yet: $DEG"
  fi

  sleep 2
done

echo "[WARN] Timeout waiting degraded_tools.json."
exit 6
