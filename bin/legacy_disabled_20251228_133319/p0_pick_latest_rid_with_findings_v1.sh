#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== get runs list =="
tmp="$(mktemp -d /tmp/vsp_pickrid_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

curl -fsS "$BASE/api/vsp/runs?limit=60&offset=0" -o "$tmp/runs.json"

python3 - <<'PY'
import json,sys,subprocess,urllib.parse,os
BASE=os.environ.get("BASE","http://127.0.0.1:8910")
runs=json.load(open(sys.argv[1],"r",encoding="utf-8"))["runs"]
paths=["reports/findings_unified.json","report/findings_unified.json","findings_unified.json"]
def try_one(rid):
    for p in paths:
        url=f"{BASE}/api/vsp/run_file_allow?rid={urllib.parse.quote(rid)}&path={urllib.parse.quote(p)}&limit=1"
        try:
            out=subprocess.check_output(["curl","-sS","-L",url], timeout=3).decode("utf-8","replace").strip()
            j=json.loads(out)
            meta=(j.get("meta") or {})
            counts=(meta.get("counts_by_severity") or meta.get("counts_total") or {})
            if isinstance(counts,dict) and any(int(v or 0)>0 for v in counts.values()):
                return p, counts
        except Exception:
            continue
    return None, None

for r in runs:
    rid=r.get("rid","")
    if not rid: 
        continue
    p,counts=try_one(rid)
    if p:
        print("PICK_RID=",rid)
        print("PATH=",p)
        print("COUNTS=",counts)
        sys.exit(0)
print("PICK_RID= (none found in last 60)")
PY "$tmp/runs.json"
