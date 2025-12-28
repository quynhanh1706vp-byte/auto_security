#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/test/Data/SECURITY_BUNDLE/out"
python3 - <<'PY'
import os, json
from glob import glob

def load_items(fp):
    try:
        j=json.load(open(fp,"r",encoding="utf-8"))
    except Exception:
        return 0, "bad_json"
    if isinstance(j,list):
        return len(j), "list"
    if isinstance(j,dict):
        for k in ("items","findings","results","data"):
            v=j.get(k)
            if isinstance(v,list):
                return len(v), f"dict.{k}"
        return 0, "dict.no_items_key"
    return 0, "unknown"

rows=[]
for d in sorted(glob(os.path.join(ROOT,"RUN_*")), reverse=True):
    fp1=os.path.join(d,"reports","findings_unified.json")
    fp2=os.path.join(d,"findings_unified.json")
    fp = fp1 if os.path.isfile(fp1) else (fp2 if os.path.isfile(fp2) else "")
    if not fp: 
        continue
    n, mode = load_items(fp)
    rid=os.path.basename(d)
    rows.append((n, rid, fp, mode))

rows.sort(reverse=True, key=lambda x: (x[0], x[1]))
print("TOP 15 runs by findings count:")
for n,rid,fp,mode in rows[:15]:
    print(f"{n:6d}  {rid}  ({mode})  {fp}")
print("\nSuggestion:")
nz=[r for r in rows if r[0]>0]
print("first_nonzero =", (nz[0][1] if nz else "NONE (all zero)"))
PY
