#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

E="$(ls -1dt out_ci/p56h4b_runtime_* 2>/dev/null | head -n 1 || true)"
if [ -z "${E:-}" ] || [ ! -d "$E" ]; then
  echo "[ERR] cannot find out_ci/p56h4b_runtime_*"; exit 2
fi
echo "E=$E"

python3 - <<'PY'
import json, re
from pathlib import Path
E = Path(list(__import__("glob").glob("out_ci/p56h4b_runtime_*"))[-1])  # not used; replaced below
PY
python3 - <<'PY'
import json, re
from pathlib import Path

import glob
E = Path(sorted(glob.glob("out_ci/p56h4b_runtime_*"))[-1])
pe = E/"pageerror.jsonl"
ce = E/"console.jsonl"
nf = E/"navfail.jsonl"
rf = E/"requestfailed.jsonl"

def head(path, n=12):
    if not path.exists(): return
    print(f"\n== {path.name} (head {n}) ==")
    for i, line in enumerate(path.read_text(errors="replace").splitlines()[:n], 1):
        print(f"{i:02d}: {line[:220]}")

def summarize_pageerrors():
    if not pe.exists():
        print("\n== pageerror: (missing) =="); return
    msgs=[]
    for line in pe.read_text(errors="replace").splitlines():
        try:
            j=json.loads(line)
        except: 
            continue
        msg=j.get("message","")
        st=str(j.get("stack",""))
        # extract first "file:line:col" occurrence
        m=re.search(r'((?:https?://|/).*?\.js):(\d+):(\d+)', st)
        where=f"{m.group(1)}:{m.group(2)}:{m.group(3)}" if m else "unknown"
        msgs.append((msg, where))
    from collections import Counter
    c=Counter(msgs)
    print("\n== pageerror summary (top) ==")
    for (msg, where), cnt in c.most_common(20):
        print(f"- x{cnt} :: {where} :: {msg[:160]}")

print(f"== evidence_dir ==\n{E}\n")

summarize_pageerrors()
head(nf, 20)
head(rf, 20)
head(ce, 30)
head(pe, 30)

# list screenshots
pngs=sorted([p.name for p in E.glob("*.png")])
print("\n== screenshots ==")
for x in pngs[:50]:
    print("-", x)
PY
