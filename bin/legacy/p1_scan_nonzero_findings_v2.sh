#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-/home/test/Data/SECURITY_BUNDLE/out}"

python3 - "$ROOT" <<'PY'
import os, json, sys
from glob import glob

ROOT = sys.argv[1]

def count_findings(fp):
    try:
        j = json.load(open(fp, "r", encoding="utf-8"))
    except Exception:
        return None, "bad_json"
    if isinstance(j, list):
        return len(j), "list"
    if isinstance(j, dict):
        # ưu tiên key findings (theo file của bạn đang có)
        if isinstance(j.get("findings"), list):
            return len(j["findings"]), "dict.findings"
        # fallback cho các schema khác
        for k in ("items","results","data"):
            v = j.get(k)
            if isinstance(v, list):
                return len(v), f"dict.{k}"
        return 0, "dict.no_list_key"
    return 0, "unknown"

rows = []
for d in sorted(glob(os.path.join(ROOT, "RUN_*")), reverse=True):
    cand = [
        os.path.join(d, "reports", "findings_unified.json"),
        os.path.join(d, "findings_unified.json"),
        os.path.join(d, "reports", "findings_unified_v2.json"),
    ]
    fp = next((c for c in cand if os.path.isfile(c)), None)
    if not fp:
        continue
    n, mode = count_findings(fp)
    if n is None:
        continue
    rid = os.path.basename(d)
    rows.append((n, rid, fp, mode))

rows.sort(key=lambda x: (x[0], x[1]), reverse=True)

print("TOP 20 runs by findings count:")
for n, rid, fp, mode in rows[:20]:
    print(f"{n:6d}  {rid}  ({mode})  {fp}")

nz = [r for r in rows if r[0] > 0]
print("\nfirst_nonzero =", (nz[0][1] if nz else "NONE (all runs are zero)"))
PY
