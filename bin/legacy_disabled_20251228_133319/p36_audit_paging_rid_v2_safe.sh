#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need awk; need head; need wc

warm(){
  for i in $(seq 1 40); do
    if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
      echo "[OK] selfcheck ok (try#$i)"
      return 0
    fi
    sleep 0.2
  done
  echo "[ERR] selfcheck not OK"
  return 2
}

fetch(){
  local url="$1" hdr="$2" out="$3"
  curl -sS -D "$hdr" -o "$out" "$url" || true
  echo "-- $url --"
  awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Length:|^Location:/{print}' "$hdr" || true
  echo "body_bytes=$(wc -c <"$out" 2>/dev/null || echo 0)"
  echo "body_head:"
  head -c 240 "$out"; echo
  echo
}

echo "== [0] warm =="
warm

echo "== [1] fetch runs (must be JSON) =="
URL_RUNS="$BASE/api/vsp/runs?limit=5&offset=0"
fetch "$URL_RUNS" /tmp/_p36_runs.hdr /tmp/_p36_runs.bin

CT="$(awk 'BEGIN{IGNORECASE=1} /^Content-Type:/{print $0; exit}' /tmp/_p36_runs.hdr | tr -d '\r' )"
echo "Content-Type(first)=$CT"

if ! echo "$CT" | grep -qi 'application/json'; then
  echo "[ERR] /api/vsp/runs is not JSON -> cannot continue P36."
  echo "Tip: check service log:"
  echo "  sudo journalctl -u vsp-ui-8910.service -n 80 --no-pager"
  exit 2
fi

RID="$(python3 - <<'PY'
import json
j=json.load(open("/tmp/_p36_runs.bin","r",encoding="utf-8", errors="replace"))
runs=j.get("runs") or []
print((runs[0].get("id") if runs else "") or "")
PY
)"
echo "== [1b] picked RID =="
echo "RID=$RID"
[ -n "$RID" ] || { echo "[ERR] RID empty"; exit 2; }

show(){
  local url="$1"
  fetch "$url" /tmp/_p36.hdr /tmp/_p36.bin
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
