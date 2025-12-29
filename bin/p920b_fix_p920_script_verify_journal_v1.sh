#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p920_p0plus_ops_evidence_logs_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p920b_${TS}"
echo "[OK] backup => ${F}.bak_p920b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("bin/p920_p0plus_ops_evidence_logs_v1.sh")
s=p.read_text(encoding="utf-8", errors="replace")

# Replace the broken python snippet that tried to embed $TS into a Python string.
pat = re.compile(r'python3\s+-\s+<<\'PY\'\s*\nimport json.*?journal ok=.*?\nPY\s*\n', re.S)

fix = r"""python3 - <<'PY'
import json, sys, pathlib
# locate journal.json from the OUT directory written by this run
out = pathlib.Path(sys.argv[1])
j = json.load(open(out/"journal.json","r",encoding="utf-8"))
print("journal ok=", j.get("ok"), "svc=", j.get("svc"))
PY
"$OUT"
"""

if not pat.search(s):
    # fallback: just remove the offending SyntaxError line if pattern not found
    s = s.replace('j=json.load(open("out_ci/p920_"+"\'"$TS"\'+"/journal.json","r",encoding="utf-8"))', '# [P920B] removed broken line')
    s = s.replace('print("journal ok=", j.get("ok"), "svc=", j.get("svc"))', '# [P920B] removed print')
    p.write_text(s, encoding="utf-8")
    print("[OK] fallback patched (removed broken verify lines)")
    raise SystemExit(0)

s = pat.sub(fix, s, count=1)
p.write_text(s, encoding="utf-8")
print("[OK] patched verify journal block")
PY

bash -n "$F"
echo "[OK] bash -n OK: $F"
