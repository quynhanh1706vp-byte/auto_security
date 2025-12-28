#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import os, glob

roots=["/home/test/Data/SECURITY-10-10-v4/out_ci","/home/test/Data/SECURITY_BUNDLE/out_ci","/home/test/Data/SECURITY_BUNDLE/out"]
def has_details(run_dir):
    # strongest signals
    fu=os.path.join(run_dir,"findings_unified.json")
    if os.path.isfile(fu) and os.path.getsize(fu)>500:
        return True, "findings_unified.json"
    # any tool raw outputs likely to contain findings
    pats=["**/*semgrep*.json","**/*bandit*.json","**/*gitleaks*.json","**/*kics*.json","**/*trivy*.json","**/*grype*.json",
          "**/*codeql*.sarif","**/*.sarif"]
    for pat in pats:
        for f in glob.glob(os.path.join(run_dir,pat), recursive=True):
            try: sz=os.path.getsize(f)
            except: continue
            if sz>800 and "reports/findings_unified.sarif" not in f:
                return True, os.path.relpath(f, run_dir)
    # csv with >1 line
    csvp=os.path.join(run_dir,"reports","findings_unified.csv")
    if os.path.isfile(csvp) and os.path.getsize(csvp)>120:
        with open(csvp,"r",encoding="utf-8",errors="ignore") as fd:
            lines=0
            for _ in fd:
                lines += 1
                if lines>=2: break
        if lines>=2:
            return True, "reports/findings_unified.csv"
    return False, ""

cands=[]
for root in roots:
    if not os.path.isdir(root): 
        continue
    for rid in os.listdir(root):
        run_dir=os.path.join(root,rid)
        if not os.path.isdir(run_dir): 
            continue
        ok,why=has_details(run_dir)
        if ok:
            cands.append((int(os.path.getmtime(run_dir)), rid, root, why))
cands.sort(reverse=True)
print("TOP 20 RID with details:")
for m,rid,root,why in cands[:20]:
    print(rid, "root=",root, "why=",why)
PY
