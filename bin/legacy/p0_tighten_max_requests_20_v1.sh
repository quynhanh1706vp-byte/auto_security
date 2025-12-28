#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p1_ui_8910_single_owner_start_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_tightmax_${TS}"
echo "[BACKUP] ${F}.bak_tightmax_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("bin/p1_ui_8910_single_owner_start_v2.sh")
s=p.read_text(encoding="utf-8", errors="replace")

s2 = s
s2 = re.sub(r'--max-requests\s+\d+', '--max-requests 20', s2)
s2 = re.sub(r'--max-requests-jitter\s+\d+', '--max-requests-jitter 5', s2)

if s2 == s:
    print("[WARN] no changes applied (flags not found?)")
else:
    p.write_text(s2, encoding="utf-8")
    print("[OK] tightened: --max-requests 20, --max-requests-jitter 5")
PY

bash -n "$F"
echo "[OK] bash -n OK"
