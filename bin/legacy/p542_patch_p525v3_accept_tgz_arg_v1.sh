#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p525_verify_release_and_customer_smoke_v3.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p542_${TS}"
echo "[OK] backup => ${F}.bak_p542_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("bin/p525_verify_release_and_customer_smoke_v3.sh")
s=p.read_text(encoding="utf-8", errors="replace")

if "P542_ACCEPT_TGZ_ARG_V1" in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Inject TGZ arg handling right after set -euo pipefail block (early)
marker = "set -euo pipefail"
idx = s.find(marker)
if idx < 0:
    raise SystemExit("[ERR] cannot find 'set -euo pipefail'")

ins = r'''
# [P542_ACCEPT_TGZ_ARG_V1] allow passing TGZ path explicitly
TGZ_ARG="${1:-}"
if [ -n "$TGZ_ARG" ]; then
  if [ -f "$TGZ_ARG" ]; then
    # normalize to absolute path
    TGZ_ARG="$(python3 - <<'P'
import os,sys
print(os.path.abspath(sys.argv[1]))
P
"$TGZ_ARG")"
  else
    echo "[WARN] TGZ_ARG provided but not found: $TGZ_ARG (fallback to latest)" >&2
    TGZ_ARG=""
  fi
fi
'''
# place after marker line
lines = s.splitlines(True)
out=[]
done=False
for line in lines:
    out.append(line)
    if (not done) and marker in line:
        out.append(ins)
        done=True

s2="".join(out)

# Replace assignment to tgz=... to honor TGZ_ARG if set.
# We do a conservative replace: first occurrence of 'tgz="$(ls -1 ... )"' block
# If pattern not found, we just insert a check after 'tgz=' echo later.
pat = r'tgz="\$\((?:.|\n){0,200}?head -n1 \|\| true\)\)"'
m = re.search(pat, s2)
if m:
    repl = 'tgz="${TGZ_ARG:-$((ls -1 "$latest_dir"/*.tgz 2>/dev/null | head -n1 || true))}"'
    s2 = s2[:m.start()] + repl + s2[m.end():]
else:
    # fallback: after tgz=... line if exists
    s2 = re.sub(r'(tgz="[^"]+")',
                r'\1\nif [ -n "$TGZ_ARG" ]; then tgz="$TGZ_ARG"; fi',
                s2, count=1)

p.write_text(s2, encoding="utf-8")
print("[OK] patched P525v3 to accept TGZ arg")
PY

bash -n "$F"
echo "[OK] bash -n PASS"
