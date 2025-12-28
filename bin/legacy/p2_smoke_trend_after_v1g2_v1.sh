#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
ERRLOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log"

echo "== [0] restart service =="
sudo systemctl restart "$SVC"

echo "== [1] wait ui_health_v2 ok =="
ok=0
for i in $(seq 1 40); do
  j="$(curl -sS "$BASE/api/vsp/ui_health_v2" || true)"
  if echo "$j" | grep -q '"ok"[[:space:]]*:[[:space:]]*true'; then
    echo "[OK] ui_health_v2 ok (try=$i)"
    ok=1
    break
  fi
  sleep 0.25
done
if [ "$ok" -ne 1 ]; then
  echo "[WARN] ui_health_v2 not ok after wait; continue anyway"
fi

RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
URL="$BASE/api/vsp/trend_v1?rid=$RID&limit=6"
tmp="$(mktemp -d /tmp/vsp_trend_v1g2_XXXXXX)"
hdr="$tmp/hdr.txt"
body="$tmp/body.txt"

echo "== [2] fetch trend_v1 with headers =="
echo "[INFO] RID=$RID"
echo "[INFO] URL=$URL"
curl -sS -D "$hdr" -o "$body" "$URL" || true

echo "== [HDR] =="
sed -n '1,25p' "$hdr" || true

echo "== [BODY first 2 lines] =="
sed -n '1,2p' "$body" || true

echo "== [marker] =="
grep -oE '"marker"\s*:\s*"[^"]+"' "$body" || echo "(no marker found)"

echo "== [parse totals] =="
python3 - "$body" <<'PY'
import json,sys
p=sys.argv[1]
b=open(p,"rb").read()
if not b.strip():
    print("EMPTY_BODY")
    raise SystemExit(2)
j=json.loads(b.decode("utf-8","replace"))
print("ok=", j.get("ok"), "marker=", j.get("marker"), "points=", len(j.get("points") or []))
for pt in (j.get("points") or [])[:6]:
    print("-", pt.get("run_id"), "total=", pt.get("total"))
PY

echo "== [tail error log] =="
tail -n 60 "$ERRLOG" 2>/dev/null || echo "(no error log)"
echo "[INFO] tmp=$tmp"
