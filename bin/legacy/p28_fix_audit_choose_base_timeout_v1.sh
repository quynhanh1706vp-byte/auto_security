#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/commercial_ui_audit_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_choosebase_to_${TS}"
echo "[BACKUP] ${F}.bak_choosebase_to_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("bin/commercial_ui_audit_v2.sh")
s=p.read_text(encoding="utf-8", errors="replace")

# bump choose_base curl max-time from 2 -> 8, connect-time 1 -> 2
pat = r'curl -fsS (--connect-timeout )1( --max-time )2( -o /dev/null "\$b/vsp5")'
if re.search(pat, s):
    s2 = re.sub(pat, r'curl -fsS \g<1>2\g<2>8\3', s, count=1)
    p.write_text(s2, encoding="utf-8")
    print("[OK] patched _choose_base timeouts to connect=2s max=8s")
else:
    # fallback: patch any choose_base line that has max-time 2 and /vsp5
    s2 = s.replace('--max-time 2 -o /dev/null "$b/vsp5"', '--max-time 8 -o /dev/null "$b/vsp5"')
    if s2 != s:
        p.write_text(s2, encoding="utf-8")
        print("[OK] patched _choose_base max-time to 8s (fallback)")
    else:
        print("[WARN] could not locate _choose_base curl line to patch")
PY
