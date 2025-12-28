#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"; TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p63_rid_latest_${TS}"; mkdir -p "$EVID"

fetch_and_pick(){
  local url="$1" out="$2"
  curl -fsS --connect-timeout 2 --max-time 8 --retry 3 --retry-all-errors \
    "$BASE$url" -o "$out" || return 1
  python3 - "$out" <<'PY'
import json,sys
p=sys.argv[1]
raw=open(p,"rb").read()
try:
  j=json.loads(raw.decode("utf-8","replace"))
except Exception:
  print("")
  raise SystemExit(0)
def pick(j):
  if isinstance(j,dict):
    for k in ("rid","run_id","request_id","req_id"):
      v=j.get(k)
      if v: return v
    for arrk in ("items","points","runs"):
      arr=j.get(arrk)
      if isinstance(arr,list) and arr:
        x=arr[0]
        if isinstance(x,dict):
          for k in ("rid","run_id","request_id","req_id"):
            v=x.get(k)
            if v: return v
  return ""
print(pick(j))
PY
}

RID=""
RID="$(fetch_and_pick "/api/vsp/top_findings_v2?limit=1" "$EVID/top_findings.json" || true)"
[ -n "$RID" ] || RID="$(fetch_and_pick "/api/vsp/datasource?lite=1" "$EVID/datasource.json" || true)"
[ -n "$RID" ] || RID="$(fetch_and_pick "/api/vsp/trend_v1" "$EVID/trend.json" || true)"

echo "RID=$RID"
echo "$RID" > "$EVID/rid.txt"
echo "[EVID] $EVID"
