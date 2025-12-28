#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/test/Data/SECURITY-10-10-v4/out_ci"
N="${1:-20}"

python3 - <<PY
import os, json, glob
root="$ROOT"
dirs=sorted([d for d in glob.glob(os.path.join(root,"VSP_CI_*")) if os.path.isdir(d)])[-int("$N"):]
cnt=0
for out_dir in dirs:
    gp=os.path.join(out_dir,"gate_policy.json")
    if os.path.isfile(gp) and os.path.getsize(gp)>0:
        continue
    rgp=os.path.join(out_dir,"run_gate_summary.json")
    if not os.path.isfile(rgp):
        continue
    try:
        rg=json.load(open(rgp,"r",encoding="utf-8"))
    except Exception:
        rg={}
    verdict=(rg.get("overall") or rg.get("overall_status") or rg.get("overall_verdict") or "UNKNOWN")
    obj={"ok":True,"verdict":str(verdict).upper(),"reasons":[f"backfill_from_run_gate_summary overall={verdict}"],"degraded_n":0}
    json.dump(obj, open(gp,"w",encoding="utf-8"), ensure_ascii=False, indent=2)
    cnt+=1
print("[OK] backfilled", cnt, "runs")
PY
