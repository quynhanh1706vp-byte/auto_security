#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== [A] GET /api/vsp/rule_overrides_v1 raw headers =="
curl -sS -D- -o /tmp/_ro_body.bin "$BASE/api/vsp/rule_overrides_v1" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Location:|^Content-Length:/{print}'
echo "== [A] first 240 bytes body =="
head -c 240 /tmp/_ro_body.bin; echo

echo "== [B] GET with trailing slash (if any) =="
curl -sS -D- -o /tmp/_ro_body_slash.bin "$BASE/api/vsp/rule_overrides_v1/" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Location:|^Content-Length:/{print}'
echo "== [B] first 240 bytes body =="
head -c 240 /tmp/_ro_body_slash.bin; echo

echo "== [C] If JSON, validate quickly =="
ct=$(grep -i '^Content-Type:' -m1 /tmp/_ro_body.bin 2>/dev/null || true)
if echo "$ct" | grep -qi 'application/json'; then
  python3 - <<'PY'
import json
data=open("/tmp/_ro_body.bin","rb").read().decode("utf-8","replace")
j=json.loads(data)
print("[OK] JSON parsed. keys=", list(j.keys())[:20])
print("ok=", j.get("ok"), "total=", j.get("total"), "path=", j.get("path"))
PY
else
  echo "[INFO] not JSON on non-slash endpoint"
fi
