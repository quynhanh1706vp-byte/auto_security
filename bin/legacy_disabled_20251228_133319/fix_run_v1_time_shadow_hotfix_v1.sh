#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_time_shadow_${TS}"
echo "[BACKUP] $F.bak_fix_time_shadow_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="replace")

# hotfix: thay mọi "time.time()" -> "__import__('time').time()"
# (tránh bị shadow local var time trong bất kỳ function nào)
new, n = re.subn(r'\btime\.time\(\)', "__import__('time').time()", txt)

p.write_text(new, encoding="utf-8")
print("[OK] replaced time.time() count =", n)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
