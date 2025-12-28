#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

LOCK="out_ci/ui_8910.lock"
PIDF="out_ci/ui_8910.pid"
LOG="out_ci/ui_8910.log"

echo "== [1] lock status =="
ls -la "$LOCK" "$PIDF" 2>/dev/null || true
if [ -f "$LOCK" ]; then
  age=$(( $(date +%s) - $(stat -c %Y "$LOCK") ))
  echo "[LOCK] age_sec=$age"
  # if no restart script running -> treat as stale lock
  if ! ps -ef | grep -E "restart_8910_gunicorn" | grep -v grep >/dev/null 2>&1; then
    echo "[LOCK] no restart process detected -> remove stale lock"
    rm -f "$LOCK"
  else
    echo "[LOCK] restart process is running -> do not remove lock"
  fi
fi

echo "== [2] restart commercial =="
./bin/restart_8910_gunicorn_commercial_v5.sh || true

echo "== [3] healthz =="
curl -sS -D- http://127.0.0.1:8910/healthz -o /tmp/healthz_8910.json || true
echo
cat /tmp/healthz_8910.json || true
echo

echo "== [4] verify run_status_v2 injection =="
RID="$(curl -sS "http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1" | jq -r '.items[0].run_id')"
echo "RID=$RID"
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" | jq '{ok,error:(.error//null), ci_run_dir, overall_verdict, has_semgrep:has("semgrep_summary"), has_trivy:has("trivy_summary"), degraded_n:(.degraded_tools|length)}'

echo "== [5] last UI log lines (for root cause if still bad) =="
tail -n 120 "$LOG" 2>/dev/null || true
