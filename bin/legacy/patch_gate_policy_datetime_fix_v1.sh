#!/usr/bin/env bash
set -euo pipefail
F="/home/test/Data/SECURITY_BUNDLE/bin/vsp_gate_policy_commercial_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

if grep -q "datetime.UTC" "$F"; then
  echo "[OK] already fixed: $F"
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_dt_${TS}"
echo "[BACKUP] $F.bak_dt_${TS}"

python3 - "$F" <<'PY'
import sys, re
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="ignore")

# ensure import has timezone support
if "import datetime" in s and "datetime.UTC" not in s:
    pass

# replace utcnow() with now(datetime.UTC)
s2 = s.replace('datetime.datetime.utcnow().isoformat() + "Z"',
               'datetime.datetime.now(datetime.UTC).isoformat().replace("+00:00","Z")')

p.write_text(s2, encoding="utf-8")
print("[OK] patched", p)
PY
