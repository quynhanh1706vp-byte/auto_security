#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-}"
N="${N:-8}"                 # set N=#workers*2 if you want
MAX_WAIT_SEC="${MAX_WAIT_SEC:-45}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

[ -n "$RID" ] || { echo "[ERR] RID is required (export RID=...)"; exit 2; }

URL_FIND="$BASE/api/vsp/findings_page_v3?rid=$RID&limit=1&offset=0"
URL_RUNS="$BASE/api/vsp/runs?limit=1&offset=0"
URL_VSP5="$BASE/vsp5"

echo "[INFO] BASE=$BASE RID=$RID N=$N MAX_WAIT_SEC=$MAX_WAIT_SEC"
echo "[INFO] warmup URL=$URL_FIND"

# 0) Wait service/port ready
t0="$(date +%s)"
ok=0
while true; do
  # Prefer a UI route because it hits gateway+templates too
  if curl -fsS --connect-timeout 1 --max-time 2 "$URL_VSP5" -o /dev/null; then
    ok=1; break
  fi
  now="$(date +%s)"
  if [ $((now - t0)) -ge "$MAX_WAIT_SEC" ]; then
    echo "[WARN] UI not ready after ${MAX_WAIT_SEC}s (svc may be activating). Continue warmup best-effort."
    break
  fi
  sleep 0.5
done
[ "$ok" -eq 1 ] && echo "[OK] UI ready for warmup" || echo "[WARN] UI not confirmed ready"

# 1) Warmup sequential once (best-effort)
curl -fsS --connect-timeout 1 --max-time 6 "$URL_RUNS" -o /dev/null || true
curl -fsS --connect-timeout 1 --max-time 6 "$URL_FIND" -o /dev/null || true

# 2) Parallel warmup (clean output, no interleaving)
# Each worker prints one line: warm#i code=XYZ t=...
echo "[INFO] parallel N=$N"
i=1
while [ "$i" -le "$N" ]; do
  (
    out="$(curl -sS --connect-timeout 1 --max-time 8 -o /dev/null -w "code=%{http_code} t=%{time_total}" "$URL_FIND" || echo "code=000 t=9.999")"
    echo "[warm#$i] $out"
  ) &
  i=$((i+1))
done
wait

echo "[OK] warmup done"
