#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need awk

echo "== [1] pick RID latest =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1&offset=0" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
runs=j.get("runs") or []
print((runs[0].get("id") if runs else "") or "")
PY
)"
echo "RID=$RID"
[ -n "$RID" ] || { echo "[ERR] cannot pick RID"; exit 2; }

show(){
  local url="$1"
  echo "-- $url --"
  curl -sS -D /tmp/_p36.hdr -o /tmp/_p36.bin "$url" || true
  awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Length:/{print}' /tmp/_p36.hdr
  head -c 220 /tmp/_p36.bin; echo
  echo
}

echo "== [2] findings paging =="
show "$BASE/api/vsp/findings?limit=5&offset=0"
show "$BASE/api/vsp/findings?limit=5&offset=5"
show "$BASE/api/vsp/findings?limit=5&offset=999999"

echo "== [3] datasource_v2 rid correctness =="
show "$BASE/api/vsp/datasource_v2"
show "$BASE/api/vsp/datasource_v2?rid=$RID"
show "$BASE/api/vsp/datasource_v2?rid=RID_DOES_NOT_EXIST_123"

echo "== [4] per-rid unified endpoints =="
show "$BASE/api/vsp/findings_unified_v1/$RID"
show "$BASE/api/vsp/findings_unified_v1/RID_DOES_NOT_EXIST_123"

echo "== [5] speed quick (optional) =="
curl -sS -o /dev/null -w "findings t=%{time_total}\n" "$BASE/api/vsp/findings?limit=5&offset=0" || true
curl -sS -o /dev/null -w "datasource_v2 t=%{time_total}\n" "$BASE/api/vsp/datasource_v2?rid=$RID" || true
