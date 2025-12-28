#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need date; need head; need sed; need wc

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${1:-}"

if [ -z "$RID" ]; then
  RID="$(curl -fsS "$BASE/api/ui/runs_v3?limit=1&include_ci=1" \
    | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j["items"][0]["rid"])')"
fi

echo "[INFO] BASE=$BASE"
echo "[INFO] RID=$RID"

HDR="/tmp/vsp_topfind_hdr_$$.txt"
BODY="/tmp/vsp_topfind_body_$$.bin"
trap 'rm -f "$HDR" "$BODY"' EXIT

URL="$BASE/api/vsp/top_findings_v2?limit=20&rid=$RID"

echo "== [A] fetch (no pipe) =="
code="$(curl -sS --max-time 15 -D "$HDR" -o "$BODY" -w "%{http_code}" "$URL" || true)"
ct="$(awk 'BEGIN{IGNORECASE=1} /^Content-Type:/ {print $0}' "$HDR" | tail -n 1 | sed 's/\r$//')"
len="$(wc -c < "$BODY" | tr -d ' ')"

echo "[STAT] http_code=$code body_bytes=$len"
echo "[STAT] $ct"
echo "--- headers (top 25) ---"
head -n 25 "$HDR" | sed 's/\r$//'
echo "--- body head (first 220 bytes, safe) ---"
head -c 220 "$BODY" | sed 's/[^[:print:]\t ]/./g'
echo

echo "== [B] JSON shape (if valid JSON) =="
python3 - <<PY
import json,sys
p="$BODY"
try:
    b=open(p,'rb').read()
    if not b.strip():
        print("EMPTY_BODY")
        sys.exit(2)
    # allow leading whitespace
    j=json.loads(b.decode('utf-8', errors='replace'))
except Exception as e:
    print("NOT_JSON:", repr(e))
    sys.exit(3)

if isinstance(j, dict):
    print("TYPE=dict keys=", sorted(list(j.keys()))[:80])
    for k in ["items","rows","data","result","findings"]:
        v=j.get(k)
        if isinstance(v, list):
            print("LIST_FIELD=", k, "len=", len(v))
            if v:
                if isinstance(v[0], dict):
                    print("SAMPLE_KEYS=", sorted(list(v[0].keys()))[:60])
                else:
                    print("SAMPLE_ELEM_TYPE=", type(v[0]).__name__)
            break
    else:
        print("NO_LIST_FIELD_MATCH")
elif isinstance(j, list):
    print("TYPE=list len=", len(j))
    if j and isinstance(j[0], dict):
        print("SAMPLE_KEYS=", sorted(list(j[0].keys()))[:60])
else:
    print("TYPE=", type(j).__name__)
PY

echo
echo "[NEXT] Paste back the output of section [A] + [B] if it still isn't JSON/200."
