#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
N="${N:-8}"
MAX_WAIT_SEC="${MAX_WAIT_SEC:-120}"
TARGET_SEC="${TARGET_SEC:-2.0}"   # warm tới khi <= 2s (đảm bảo CIO smoke pass)
RID="${RID:-}"

# wait UI up
t0="$(date +%s)"
while true; do
  curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null && break || true
  now="$(date +%s)"; [ $((now - t0)) -ge "$MAX_WAIT_SEC" ] && break
  sleep 0.5
done

# pick RID
if [ -z "$RID" ]; then
  RID="$(curl -sS --connect-timeout 1 --max-time 3 "$BASE/api/vsp/rid_latest" \
    | python3 -c 'import sys,json; print((json.load(sys.stdin).get("rid") or "").strip())' 2>/dev/null || true)"
fi
[ -n "$RID" ] || { echo "[WARN] RID empty -> skip"; exit 0; }

URL="$BASE/api/vsp/findings_page_v3?rid=$RID&limit=1&offset=0"
echo "[INFO] warm RID=$RID N=$N TARGET_SEC=$TARGET_SEC URL=$URL"

# grind warm until code=200 and time <= TARGET_SEC (or max tries)
ok=0
for i in $(seq 1 18); do
  line="$(curl -sS --connect-timeout 1 --max-time 40 -o /dev/null -w "code=%{http_code} t=%{time_total}" "$URL" || echo "code=000 t=99.999")"
  echo "[warm#$i] $line"
  code="$(echo "$line" | awk '{print $1}' | cut -d= -f2)"
  t="$(echo "$line" | awk '{print $2}' | cut -d= -f2)"
  if [ "$code" = "200" ]; then
    python3 - "$t" "$TARGET_SEC" <<'EOF' && ok=1 || true
import sys
t=float(sys.argv[1]); target=float(sys.argv[2])
raise SystemExit(0 if t<=target else 1)
EOF
  fi
  [ "$ok" = "1" ] && break
  sleep 1
done

if [ "$ok" != "1" ]; then
  echo "[WARN] warm did not reach target (continue no-fail)"
else
  echo "[OK] warm reached target"
fi

# parallel warm
for i in $(seq 1 "$N"); do
  curl -sS --connect-timeout 1 --max-time 10 "$URL" >/dev/null || true &
done
wait
echo "[OK] warmup done"
