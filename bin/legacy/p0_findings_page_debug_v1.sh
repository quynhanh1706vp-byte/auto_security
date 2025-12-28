#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); r=(j.get("runs") or [{}])[0]; print(r.get("rid") or r.get("run_id") or "")')"
echo "[RID]=$RID"

TMP="/tmp/vsp_findings_page.$$"
HTTP="$(curl -sS -w "%{http_code}" "$BASE/api/vsp/findings_page?rid=$RID&offset=0&limit=3&debug=1" -o "$TMP" || true)"
echo "[HTTP]=$HTTP bytes=$(wc -c <"$TMP" 2>/dev/null || echo 0)"
echo "---- BODY (first 400 chars) ----"
head -c 400 "$TMP"; echo
echo "---- JSON pretty (best effort) ----"
python3 - <<PY || true
import json
raw=open("$TMP","rb").read().decode("utf-8","replace")
print(json.dumps(json.loads(raw), ensure_ascii=False, indent=2)[:2000])
PY
rm -f "$TMP" || true
