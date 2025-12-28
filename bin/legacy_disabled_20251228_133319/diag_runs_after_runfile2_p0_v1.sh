#!/usr/bin/env bash
set -euo pipefail

HOST=127.0.0.1
PORT=8910
BASE="http://${HOST}:${PORT}"
URL="${BASE}/api/vsp/runs?limit=5"
SVC="vsp-ui-8910.service"
UI="/home/test/Data/SECURITY_BUNDLE/ui"
ERR="${UI}/out_ci/ui_8910.error.log"

echo "== wait LISTEN ${HOST}:${PORT} (max ~6s) =="
for i in $(seq 1 30); do
  if ss -ltnp 2>/dev/null | grep -q "${HOST}:${PORT}"; then
    echo "[OK] LISTEN at try=$i"
    break
  fi
  sleep 0.2
done

echo "== curl /api/vsp/runs headers+body snippet =="
HDR="$(mktemp)"; BODY="$(mktemp)"
set +e
curl -sS -D "$HDR" -o "$BODY" "$URL"
rc=$?
set -e
echo "[curl_rc]=$rc"

echo "--- status line ---"
sed -n '1p' "$HDR" || true
echo "--- content-type ---"
grep -i '^content-type:' "$HDR" || true
echo "--- x-vsp-runs-has ---"
grep -i '^x-vsp-runs-has:' "$HDR" || true
echo "--- first 40 header lines ---"
sed -n '1,40p' "$HDR" || true
echo "--- body first 300 bytes ---"
python3 - <<PY
b=open("$BODY","rb").read(300)
print(b.decode("utf-8","replace"))
PY

echo "== try parse json =="
python3 - <<PY
import json
from pathlib import Path
t=Path("$BODY").read_text(encoding="utf-8", errors="replace").strip()
print("body_len=", len(t))
try:
  d=json.loads(t)
  print("[OK] json keys:", list(d.keys())[:12])
  print("[OK] items=", len(d.get("items") or []))
except Exception as e:
  print("[FAIL] json parse:", e)
PY

echo "== systemctl status (top) =="
sudo systemctl --no-pager --full status "$SVC" | sed -n '1,80p' || true

echo "== journalctl (last 120) =="
sudo journalctl -u "$SVC" -n 120 --no-pager || true

echo "== tail ui_8910.error.log =="
test -f "$ERR" && tail -n 160 "$ERR" || echo "[WARN] missing $ERR"

rm -f "$HDR" "$BODY"
