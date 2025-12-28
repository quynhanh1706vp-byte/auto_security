#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

tmp="$(mktemp -d /tmp/vsp_dash_api_probe_XXXXXX)"; trap 'rm -rf "$tmp"' EXIT

probe(){
  local path="$1"
  local tag="$(echo "$path" | tr '/?=&' '____')"
  echo
  echo "=== PROBE $path ==="
  curl -sS --compressed -L -D "$tmp/$tag.h" -o "$tmp/$tag.b" "$BASE$path" || true
  echo "--- status ---"
  head -n 1 "$tmp/$tag.h" || true
  echo "--- headers (ct/location/len/enc) ---"
  grep -Ei '^(content-type:|location:|content-length:|content-encoding:|cache-control:)' "$tmp/$tag.h" || true
  echo "--- body bytes ---"
  python3 - <<PY
from pathlib import Path
b=Path("$tmp")/"$tag.b"
data=b.read_bytes() if b.exists() else b""
print("BYTES_LEN=",len(data))
print("HEAD_220=")
print(data[:220].decode("utf-8","replace"))
PY
  echo "--- json parse ---"
  python3 - <<PY
import json
from pathlib import Path
b=Path("$tmp")/"$tag.b"
raw=b.read_text(encoding="utf-8", errors="replace") if b.exists() else ""
try:
    j=json.loads(raw)
    print("JSON_OK keys=", list(j.keys())[:20])
    if isinstance(j, dict):
        for k in ("ok","err","rid","run_id","total","count","degraded"):
            if k in j: print(k,"=",j.get(k))
        for k in ("runs","items","points"):
            if k in j:
                v=j.get(k)
                if isinstance(v,list): print(k,"len=",len(v))
except Exception as e:
    print("JSON_FAIL:", type(e).__name__)
PY
}

probe "/api/vsp/rid_latest"
probe "/api/vsp/runs?limit=1"
probe "/api/vsp/runs?limit=1&offset=0"
probe "/api/vsp/runs?limit=80&offset=0"
probe "/api/vsp/ui_health_v2?rid=$(curl -fsS --compressed "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))' 2>/dev/null || true)"
probe "/api/vsp/trend_v1"
probe "/api/vsp/top_findings_v1?limit=5"

echo
echo "== tail gateway log signatures (optional) =="
ERRLOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log"
if [ -f "$ERRLOG" ]; then
  tail -n 160 "$ERRLOG" | grep -nE 'API_HIT|/api/vsp/runs|Traceback|Exception| 5[0-9][0-9] ' || true
fi
