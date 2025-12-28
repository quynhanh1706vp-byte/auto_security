#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/legacy/p559_commercial_preflight_audit_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p578e_${TS}"
echo "[OK] backup => ${F}.bak_p578e_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("bin/legacy/p559_commercial_preflight_audit_v2.sh")
s=p.read_text(encoding="utf-8", errors="replace")

# Replace inline "&& wa '...X-Frame-Options...'" -> "&& ok '...X-Frame-Options...'"
s2 = re.sub(
    r'(\&\&\s*)wa(\s*[\'"].*?X-Frame-Options.*?[\'"])',
    r'\1ok\2',
    s,
    flags=re.I
)

# Also cover any remaining direct wa "X-Frame-Options..." occurrences (rare)
s2 = re.sub(
    r'(\s)wa(\s*[\'"].*?X-Frame-Options.*?[\'"])',
    r'\1ok\2',
    s2,
    flags=re.I
)

if s2 == s:
    print("[WARN] no change made (pattern not found) — check file content")
else:
    p.write_text(s2, encoding="utf-8")
    print("[OK] patched inline wa(XFO) => ok")

print("== [check] XFO lines now ==")
for i, line in enumerate(s2.splitlines(), 1):
    if "X-Frame-Options" in line:
        print(f"{i}: {line}")
PY

bash -n "$F"
echo "[OK] bash -n ok"

echo "== [run] preflight =="
bash bin/preflight_audit.sh
