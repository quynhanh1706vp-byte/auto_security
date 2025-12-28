#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
ERRLOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log"

RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
URL="$BASE/api/vsp/trend_v1?rid=$RID&limit=12"

tmp="$(mktemp -d /tmp/vsp_trend_smoke_XXXXXX)"
hdr="$tmp/hdr.txt"
body="$tmp/body.txt"

echo "[INFO] RID=$RID"
echo "[INFO] URL=$URL"
echo "[INFO] tmp=$tmp"

# retry a few times (service may still be warming up)
ok=0
for i in 1 2 3 4 5; do
  curl -sS -D "$hdr" -o "$body" "$URL" || true
  bytes="$(wc -c <"$body" | tr -d ' ')"
  code="$(awk 'NR==1{print $2}' "$hdr" 2>/dev/null || true)"
  echo "[TRY $i] http=$code body_bytes=$bytes"
  if [ "${bytes:-0}" -gt 0 ]; then ok=1; break; fi
  sleep 0.3
done

echo "== [HDR] =="
sed -n '1,20p' "$hdr" || true
echo "== [BODY head 40 lines] =="
sed -n '1,40p' "$body" || true

echo "== [MARKER grep] =="
grep -oE '"marker"\s*:\s*"[^"]+"' "$body" || echo "(no marker found)"

echo "== [JSON parse check] =="
python3 - <<PY || true
import json,sys
p="$body"
b=open(p,"rb").read()
if not b.strip():
    print("EMPTY_BODY")
    raise SystemExit(2)
try:
    j=json.loads(b.decode("utf-8","replace"))
    print("JSON_OK keys=", list(j.keys())[:10])
    print("ok=", j.get("ok"), "marker=", j.get("marker"), "points=", len(j.get("points") or []))
except Exception as e:
    print("JSON_FAIL:", e)
    print("FIRST200=", b[:200])
PY

echo "== [TAIL error log] =="
tail -n 80 "$ERRLOG" 2>/dev/null || echo "(no error log at $ERRLOG)"
