#!/usr/bin/env bash
set -euo pipefail
BASE="http://127.0.0.1:8910"
URL="${BASE}/api/vsp/runs?limit=1"
UI="/home/test/Data/SECURITY_BUNDLE/ui"
ERR="${UI}/out_ci/ui_8910.error.log"

echo "== curl headers+body snippet =="
HDR="$(mktemp)"; BODY="$(mktemp)"
curl -sS -D "$HDR" -o "$BODY" "$URL" || true
echo "--- status line ---"
sed -n '1p' "$HDR" || true
echo "--- content-type ---"
grep -i '^content-type:' "$HDR" || true
echo "--- first 40 header lines ---"
sed -n '1,40p' "$HDR" || true
echo "--- body first 200 bytes ---"
python3 - <<PY
b=open("$BODY","rb").read(200)
print(b.decode("utf-8","replace"))
PY

echo "== try parse json (if possible) =="
python3 - <<PY
import json
from pathlib import Path
body=Path("$BODY").read_text(encoding="utf-8", errors="replace").strip()
print("body_len=", len(body))
try:
  d=json.loads(body)
  print("[OK] json keys:", list(d.keys())[:10])
except Exception as e:
  print("[FAIL] json parse:", e)
PY

echo "== tail ui_8910.error.log =="
test -f "$ERR" && tail -n 120 "$ERR" || echo "[WARN] missing $ERR"

rm -f "$HDR" "$BODY"
