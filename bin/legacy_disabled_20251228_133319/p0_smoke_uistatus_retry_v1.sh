#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
U="$BASE/api/vsp/ui_status_v1"

H="/tmp/vsp_uistatus_hdr.$$"
B="/tmp/vsp_uistatus_body.$$"

for i in $(seq 1 12); do
  curl -sS -D "$H" "$U" -o "$B" || true
  if [ -s "$B" ] && head -c 1 "$B" | grep -q '{'; then
    python3 - <<PY
import json
raw=open("$B","rb").read()
j=json.loads(raw.decode("utf-8","replace"))
print("ok=", j.get("ok"), "fails=", len(j.get("fails") or []), "warn=", len(j.get("warn") or []))
PY
    rm -f "$H" "$B" || true
    exit 0
  fi
  sleep 0.2
done

echo "[ERR] ui_status not JSON after retries"
echo "-- HEAD --"; sed -n '1,30p' "$H" || true
echo "-- BODY head --"; head -c 240 "$B" || true; echo
rm -f "$H" "$B" || true
exit 2
