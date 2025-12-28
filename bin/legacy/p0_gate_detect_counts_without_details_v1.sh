#!/usr/bin/env bash
set -euo pipefail
RID="${1:-VSP_CI_20251211_133204}"
ROOT="/home/test/Data/SECURITY-10-10-v4/out_ci"
D="$ROOT/$RID"
[ -d "$D" ] || { echo "[ERR] no dir: $D"; exit 2; }

python3 - <<'PY'
import os, json
rid=os.environ.get("RID")
d=os.environ.get("D")
gs=os.path.join(d,"run_gate_summary.json")
csvp=os.path.join(d,"reports","findings_unified.csv")
sarifp=os.path.join(d,"reports","findings_unified.sarif")
note=os.path.join(d,"NOTES_TOPFIND.txt")

def csv_has_rows(p):
    if not os.path.isfile(p) or os.path.getsize(p)<120: return False
    n=0
    with open(p,"r",encoding="utf-8",errors="ignore") as f:
        for _ in f:
            n+=1
            if n>=2: return True
    return False

def sarif_has_results(p):
    if not os.path.isfile(p) or os.path.getsize(p)<150: return False
    try:
        j=json.load(open(p,"r",encoding="utf-8",errors="ignore"))
        for run in (j.get("runs") or []):
            if (run.get("results") or []): return True
    except Exception:
        return False
    return False

j=json.load(open(gs,"r",encoding="utf-8",errors="replace"))
counts=j.get("counts_total") or {}
total=sum(int(counts.get(k,0) or 0) for k in counts.keys())
has_details = csv_has_rows(csvp) or sarif_has_results(sarifp) or os.path.isfile(os.path.join(d,"findings_unified.json"))

msg=[]
msg.append(f"RID={rid}")
msg.append(f"counts_total={total} breakdown={counts}")
msg.append(f"details: csv_rows={csv_has_rows(csvp)} sarif_results={sarif_has_results(sarifp)} findings_unified_json={os.path.isfile(os.path.join(d,'findings_unified.json'))}")
if total>0 and not has_details:
    msg.append("DEGRADED: counts exist but NO detailed findings artifacts were saved. Fix pipeline to persist tool raw outputs + unified findings.")
open(note,"w",encoding="utf-8").write("\n".join(msg)+"\n")
print("\n".join(msg))
print("wrote:", note)
PY
