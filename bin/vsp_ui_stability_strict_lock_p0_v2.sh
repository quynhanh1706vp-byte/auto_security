#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
BASE="${BASE:-http://127.0.0.1:8910}"
N="${1:-300}"
LOCK="/tmp/vsp_ui_8910.lock"

exec 9>"$LOCK"
flock -n 9 || { echo "[ERR] UI lock busy: $LOCK (stop other patch/restart/selfcheck running)"; exit 2; }

echo "== VSP UI STABILITY STRICT+LOCK P0 V2 =="
echo "[BASE]=$BASE [N]=$N [LOCK]=$LOCK"
ERRLOG="out_ci/ui_8910.error.log"
ACCLOG="out_ci/ui_8910.access.log"

pid_master(){
  # best-effort: take oldest gunicorn PID bound to 8910 as "master-ish"
  ss -lntp 2>/dev/null | awk '/:8910/ {print $NF}' | head -n1 | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | head -n1
}

dump_diag(){
  echo "== DIAG =="
  date
  ss -lntp | grep ':8910' || true
  ps -ef | grep -E 'gunicorn .*8910' | grep -v grep || true
  echo "== tail error.log =="
  tail -n 120 "$ERRLOG" 2>/dev/null || true
  echo "== tail access.log =="
  tail -n 40 "$ACCLOG" 2>/dev/null || true
}

# ensure service reachable before loop
curl -fsS --max-time 4 "$BASE/vsp4" >/dev/null

PID0="$(pid_master || true)"
echo "[PID0]=${PID0:-UNKNOWN}"

# IMPORTANT: hit ONLY commercial endpoints (avoid older heavy ones)
URLS=(
  "$BASE/vsp4"
  "$BASE/static/js/vsp_bundle_commercial_v2.js"
  "$BASE/api/vsp/latest_rid_v1"
  "$BASE/api/vsp/dashboard_commercial_v2"
  "$BASE/api/vsp/runs_index_v3_fs_resolved?limit=1"
  "$BASE/api/vsp/findings_latest_v1?limit=3"
  "$BASE/api/vsp/rule_overrides_v1"
)

for i in $(seq 1 "$N"); do
  # detect restart
  PID="$(pid_master || true)"
  if [ -n "${PID0:-}" ] && [ -n "${PID:-}" ] && [ "$PID" != "$PID0" ]; then
    echo "[FAIL] i=$i gunicorn PID changed: $PID0 -> $PID (restart detected)"
    dump_diag
    exit 3
  fi

  for u in "${URLS[@]}"; do
    # strict: no retry; if you want retry, increase --retry
    code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 6 "$u" || echo 000000)"
    if [ "$code" != "200" ]; then
      echo "[FAIL] i=$i code=$code url=$u"
      dump_diag
      exit 4
    fi
  done
done

echo "== RESULT =="
echo "[OK] stable: no non-200 + no restart in $N rounds"
