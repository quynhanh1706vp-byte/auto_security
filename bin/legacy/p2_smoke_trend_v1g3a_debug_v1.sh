#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
ERRLOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log"
ACCLOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.access.log"

echo "== [0] restart =="
sudo systemctl restart "$SVC" || true

echo "== [1] wait until /api/vsp/rid_latest returns JSON =="
ok=0
for i in $(seq 1 40); do
  if curl -fsS "$BASE/api/vsp/rid_latest" >/tmp/rid_latest.json 2>/dev/null; then
    if python3 - <<'PY' >/dev/null 2>&1
import json
json.load(open("/tmp/rid_latest.json","r",encoding="utf-8"))
PY
    then
      ok=1
      break
    fi
  fi
  sleep 0.25
done
if [ "$ok" -ne 1 ]; then
  echo "[WARN] rid_latest not stable yet; continue anyway"
fi

RID="$(python3 -c 'import json; print(json.load(open("/tmp/rid_latest.json","r",encoding="utf-8")).get("rid",""))' 2>/dev/null || true)"
[ -n "${RID:-}" ] || RID="TEST"
URL="$BASE/api/vsp/trend_v1?rid=$RID&limit=10"

tmp="$(mktemp -d /tmp/vsp_trend_v1g3a_XXXXXX)"
hdr="$tmp/hdr.txt"
body="$tmp/body.txt"

echo "[INFO] RID=$RID"
echo "[INFO] URL=$URL"
echo "[INFO] tmp=$tmp"

echo "== [2] fetch trend_v1 with retry =="
for i in $(seq 1 10); do
  rm -f "$hdr" "$body"
  curl -sS -D "$hdr" -o "$body" "$URL" || true
  bytes="$(wc -c <"$body" | tr -d ' ')"
  code="$(awk 'NR==1{print $2}' "$hdr" 2>/dev/null || true)"
  echo "[TRY $i] http=$code body_bytes=$bytes"
  if [ "${bytes:-0}" -gt 0 ]; then
    break
  fi
  sleep 0.25
done

echo "== [HDR] =="
sed -n '1,25p' "$hdr" || true

echo "== [BODY first 2 lines] =="
sed -n '1,2p' "$body" || true

echo "== [marker] =="
grep -oE '"marker"\s*:\s*"[^"]+"' "$body" || echo "(no marker)"

echo "== [parse + print totals] =="
python3 - "$body" <<'PY' || true
import json,sys
b=open(sys.argv[1],"rb").read()
if not b.strip():
    print("EMPTY_BODY"); raise SystemExit(2)
try:
    j=json.loads(b.decode("utf-8","replace"))
    print("ok=", j.get("ok"), "marker=", j.get("marker"), "points=", len(j.get("points") or []))
    for p in (j.get("points") or [])[:10]:
        print("-", p.get("run_id"), "total=", p.get("total"))
except Exception as e:
    print("JSON_FAIL:", e)
    print("FIRST200=", b[:200])
PY

echo "== [tail error log] =="
tail -n 80 "$ERRLOG" 2>/dev/null || echo "(no error log)"

echo "== [tail access log] =="
tail -n 20 "$ACCLOG" 2>/dev/null || echo "(no access log)"
