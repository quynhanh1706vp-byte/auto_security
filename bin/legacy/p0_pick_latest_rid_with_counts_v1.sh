#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

tmp="$(mktemp -d /tmp/vsp_pickrid_counts_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

curl -fsS "$BASE/api/vsp/runs?limit=80&offset=0" -o "$tmp/runs.json"

python3 - "$tmp/runs.json" <<'PY'
import json, sys, urllib.parse, subprocess

BASE="http://127.0.0.1:8910"
runs=json.load(open(sys.argv[1],"r",encoding="utf-8")).get("runs") or []

paths=["run_gate_summary.json","reports/run_gate_summary.json","report/run_gate_summary.json"]

def get(url, timeout=3):
    return subprocess.check_output(["curl","-sS","-L",url], timeout=timeout).decode("utf-8","replace")

def sum_counts(d):
    if not isinstance(d, dict): return 0
    s=0
    for k,v in d.items():
        try: s += int(v or 0)
        except: pass
    return s

for r in runs:
    rid=r.get("rid")
    if not rid: 
        continue
    for p in paths:
        url=f"{BASE}/api/vsp/run_file_allow?rid={urllib.parse.quote(rid)}&path={urllib.parse.quote(p)}"
        try:
            j=json.loads(get(url))
            counts=j.get("counts_total") or {}
            if sum_counts(counts) > 0:
                print("PICK_RID="+rid)
                print("PATH="+p)
                print("COUNTS_TOTAL="+json.dumps(counts))
                raise SystemExit(0)
        except Exception:
            continue

print("PICK_RID=")
PY
