#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need date

RID="ro_test_$(date +%s)"

echo "== GET0 =="
curl -sS -D /tmp/_ro_get0.hdr -o /tmp/_ro_get0.bin "$BASE/api/vsp/rule_overrides_v1/"
awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Length:/{print}' /tmp/_ro_get0.hdr
head -c 240 /tmp/_ro_get0.bin; echo; echo

echo "== POST =="
cat > /tmp/_ro_post.json <<JSON
{"id":"$RID","tool":"semgrep","rule_id":"TEST.P35.DEMO","action":"suppress","severity_override":"INFO","reason":"p35 smoke","enabled":true}
JSON
curl -sS -D /tmp/_ro_post.hdr -o /tmp/_ro_post.bin \
  -X POST -H 'Content-Type: application/json' --data-binary @/tmp/_ro_post.json \
  "$BASE/api/vsp/rule_overrides_v1/"
awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Length:/{print}' /tmp/_ro_post.hdr
head -c 240 /tmp/_ro_post.bin; echo; echo

echo "== GET1 (must contain created id) =="
curl -sS -o /tmp/_ro_get1.bin "$BASE/api/vsp/rule_overrides_v1/"
python3 - <<PY
import json
j=json.load(open("/tmp/_ro_get1.bin","r",encoding="utf-8"))
ids=set((x or {}).get("id") for x in (j.get("items") or []) if isinstance(x, dict))
print("has_created=", ("$RID" in ids), "total=", j.get("total"), "path=", j.get("path"))
PY
echo

echo "== DELETE =="
curl -sS -D /tmp/_ro_del.hdr -o /tmp/_ro_del.bin \
  -X DELETE "$BASE/api/vsp/rule_overrides_v1/?id=$RID"
awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Length:/{print}' /tmp/_ro_del.hdr
head -c 240 /tmp/_ro_del.bin; echo; echo

echo "== GET2 (must be removed) =="
curl -sS -o /tmp/_ro_get2.bin "$BASE/api/vsp/rule_overrides_v1/"
python3 - <<PY
import json
j=json.load(open("/tmp/_ro_get2.bin","r",encoding="utf-8"))
ids=set((x or {}).get("id") for x in (j.get("items") or []) if isinstance(x, dict))
print("removed_ok=", ("$RID" not in ids), "total=", j.get("total"))
PY
echo

echo "== persisted file =="
ls -lh /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v1/rule_overrides.json || true
