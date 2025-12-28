#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p525_verify_release_and_customer_smoke_v3.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p542b_${TS}"
echo "[OK] backup => ${F}.bak_p542b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("bin/p525_verify_release_and_customer_smoke_v3.sh")
s=p.read_text(encoding="utf-8", errors="replace")

# 1) Remove the broken P542 block if present
# We remove from marker line to the first blank line after it (safe enough).
s2 = re.sub(
    r"\n# \[P542_ACCEPT_TGZ_ARG_V1\][\s\S]*?\n(?=\n)",
    "\n",
    s,
    count=1
)

# 2) Insert a clean TGZ_ARG handler right after set -euo pipefail (or after cd line if needed)
ins = r'''
# [P542B_ACCEPT_TGZ_ARG_V2] allow passing TGZ path explicitly
TGZ_ARG="${1:-}"
if [ -n "$TGZ_ARG" ]; then
  if [ -f "$TGZ_ARG" ]; then
    TGZ_ARG="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$TGZ_ARG")"
  else
    echo "[WARN] TGZ_ARG provided but not found: $TGZ_ARG (fallback to latest)" >&2
    TGZ_ARG=""
  fi
fi
'''
if "P542B_ACCEPT_TGZ_ARG_V2" not in s2:
    if "set -euo pipefail" in s2:
        s2 = s2.replace("set -euo pipefail", "set -euo pipefail"+ins, 1)
    else:
        # fallback: after first 'cd ...' line
        s2 = re.sub(r"^(cd .*\n)", r"\1"+ins, s2, count=1, flags=re.M)

# 3) Ensure TGZ_ARG actually overrides auto-picked tgz
# After first assignment tgz="...": insert tgz override line once.
if "tgz=\"${TGZ_ARG:-$tgz}\"" not in s2:
    s2 = re.sub(r'^(tgz="[^"]*".*)$',
                r'\1\ntgz="${TGZ_ARG:-$tgz}"',
                s2,
                count=1,
                flags=re.M)

p.write_text(s2, encoding="utf-8")
print("[OK] patched TGZ_ARG handler + override")
PY

bash -n "$F"
echo "[OK] bash -n PASS"
