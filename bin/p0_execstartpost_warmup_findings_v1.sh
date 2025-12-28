#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-}"                 # optional override
N="${N:-8}"
MAX_WAIT_SEC="${MAX_WAIT_SEC:-120}"
TARGET_SEC="${TARGET_SEC:-2.0}"

cd /home/test/Data/SECURITY_BUNDLE/ui
mkdir -p out_ci
LOG="out_ci/warmup_findings.log"
DONE="out_ci/warmup_findings.done"
: > "$LOG"
rm -f "$DONE"

echo "[INFO] ExecStartPost warmup begin $(date -Is)" >>"$LOG"
echo "[INFO] BASE=$BASE N=$N MAX_WAIT_SEC=$MAX_WAIT_SEC TARGET_SEC=$TARGET_SEC" >>"$LOG"

# 1) wait UI readycheck (same as your existing readycheck, but soft)
t0="$(date +%s)"
while true; do
  ok=0
  curl -fsS --connect-timeout 1 --max-time 2 "$BASE/runs" >/dev/null && \
  curl -fsS --connect-timeout 1 --max-time 2 "$BASE/data_source" >/dev/null && \
  curl -fsS --connect-timeout 1 --max-time 2 "$BASE/settings" >/dev/null && \
  curl -fsS --connect-timeout 1 --max-time 2 "$BASE/api/vsp/runs?limit=1" >/dev/null && \
  curl -fsS --connect-timeout 1 --max-time 2 "$BASE/api/vsp/release_latest" >/dev/null && ok=1 || true

  [ "$ok" = "1" ] && break
  now="$(date +%s)"
  if [ $((now - t0)) -ge "$MAX_WAIT_SEC" ]; then
    echo "[WARN] readycheck timeout; still attempt warmup" >>"$LOG"
    break
  fi
  sleep 0.3
done

# 2) run your warmup v3 (no-fail)
echo "[INFO] run warmup v3 $(date -Is)" >>"$LOG"
N="$N" MAX_WAIT_SEC="$MAX_WAIT_SEC" TARGET_SEC="$TARGET_SEC" RID="$RID" \
  bash bin/p0_warmup_findings_after_ready_v3.sh >>"$LOG" 2>&1 || true

echo "OK" > "$DONE" || true
echo "[OK] ExecStartPost warmup done $(date -Is)" >>"$LOG"
exit 0
