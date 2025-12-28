#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); r=(j.get("runs") or [{}])[0]; print(r.get("rid") or r.get("run_id") or "")')"
echo "[RID]=$RID"

TMP="/tmp/vsp_mf.$$"
HTTP="$(curl -sS -w "%{http_code}" "$BASE/api/vsp/audit_pack_manifest?rid=$RID&lite=1" -o "$TMP" || true)"
echo "[HTTP]=$HTTP bytes=$(wc -c <"$TMP" 2>/dev/null || echo 0)"

python3 - <<PY
import json
raw=open("$TMP","rb").read()
try:
  j=json.loads(raw.decode("utf-8","replace"))
  print("ok=",j.get("ok"),"inc=",j.get("included_count"),"miss=",j.get("missing_count"),"err=",j.get("errors_count"),"run_dir=",j.get("run_dir"))
  if j.get("missing"):
    print("-- missing (first 6) --")
    for x in (j.get("missing") or [])[:6]:
      print("-", x.get("path"), x.get("reason"))
except Exception as e:
  print("[NOT JSON] head=", raw[:220])
PY

rm -f "$TMP" || true
