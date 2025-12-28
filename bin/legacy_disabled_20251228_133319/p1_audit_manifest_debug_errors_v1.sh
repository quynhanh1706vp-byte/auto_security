#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); r=(j.get("runs") or [{}])[0]; print(r.get("rid") or r.get("run_id") or "")')"
echo "[RID]=$RID"

curl -fsS "$BASE/api/vsp/audit_pack_manifest?rid=$RID&lite=1" \
| python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print("ok=", j.get("ok"), "inc=", j.get("included_count"), "miss=", j.get("missing_count"), "err=", j.get("errors_count"))
errs = j.get("errors") or []
if errs:
  print("\n-- ERRORS (path/code/err) --")
  for e in errs:
    print("-", e.get("path"), "code=", e.get("code"), "err=", (e.get("err") or "")[:120])
else:
  print("\n(no errors)")
PY
