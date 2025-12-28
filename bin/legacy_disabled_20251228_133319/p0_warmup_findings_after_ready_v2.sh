#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
N="${N:-8}"                 # ~= workers*2
MAX_WAIT_SEC="${MAX_WAIT_SEC:-90}"

# 0) wait UI up
t0="$(date +%s)"
while true; do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null; then
    break
  fi
  now="$(date +%s)"
  if [ $((now - t0)) -ge "$MAX_WAIT_SEC" ]; then
    break
  fi
  sleep 0.5
done

# 1) pick RID (prefer env, else api rid_latest)
RID="${RID:-}"
if [ -z "$RID" ]; then
  RID="$(curl -sS --connect-timeout 1 --max-time 3 "$BASE/api/vsp/rid_latest" \
    | python3 -c 'import sys,json; print((json.load(sys.stdin).get("rid") or "").strip())' 2>/dev/null || true)"
fi

if [ -z "$RID" ]; then
  echo "[WARN] RID empty -> skip findings warm"
  exit 0
fi

URL_FIND="$BASE/api/vsp/findings_page_v3?rid=$RID&limit=1&offset=0"
URL_RUNS="$BASE/api/vsp/runs?limit=1&offset=0"
echo "[INFO] warm RID=$RID N=$N"

# 2) one long warm: wait until HTTP 200 at least once
ok=0
for i in $(seq 1 12); do
  line="$(curl -sS --connect-timeout 1 --max-time 30 -o /dev/null -w "code=%{http_code} t=%{time_total}" "$URL_FIND" || echo "code=000 t=99.999")"
  echo "[warm1#$i] $line"
  code="$(echo "$line" | awk '{print $1}' | cut -d= -f2)"
  if [ "$code" = "200" ]; then ok=1; break; fi
  sleep 1
done

# also touch /runs once (helps gateway/worker warm)
curl -fsS --connect-timeout 1 --max-time 10 "$URL_RUNS" >/dev/null || true

if [ "$ok" -ne 1 ]; then
  echo "[WARN] cannot warm findings to 200 (no-fail)"
  exit 0
fi

# 3) parallel warm (short)
for i in $(seq 1 "$N"); do
  curl -sS --connect-timeout 1 --max-time 10 "$URL_FIND" >/dev/null || true &
done
wait
echo "[OK] warmup done"
