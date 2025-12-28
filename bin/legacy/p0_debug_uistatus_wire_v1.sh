#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
U="$BASE/api/vsp/ui_status_v1"
H="/tmp/vsp_uistatus_hdr.$$.txt"
B="/tmp/vsp_uistatus_body.$$.bin"

echo "== GET $U =="
curl -sS -D "$H" "$U" -o "$B" || true

echo
echo "-- STATUS/HEADERS --"
sed -n '1,30p' "$H" || true

echo
echo "-- BODY first 240 bytes (printable) --"
python3 - <<PY
import pathlib, re
b = pathlib.Path("$B").read_bytes()
print("bytes=", len(b))
head = b[:240]
# show as safe text + also raw hex for first 64
try:
    t = head.decode("utf-8", "replace")
except Exception:
    t = str(head)
print(t.replace("\n","\\n"))
print("hex64=", head[:64].hex())
PY

echo
echo "-- JSON parse attempt --"
python3 - <<PY
import json, pathlib
raw = pathlib.Path("$B").read_bytes()
try:
    j = json.loads(raw.decode("utf-8","replace"))
    print("JSON_OK ok=", j.get("ok"), "fails=", len(j.get("fails") or []), "warn=", len(j.get("warn") or []))
except Exception as e:
    print("NOT_JSON:", e)
PY

rm -f "$H" "$B" || true
echo "[DONE]"
