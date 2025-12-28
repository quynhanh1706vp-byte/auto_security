#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F=".github/workflows/vsp_p0_commercial_gate.yml"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_pin_${TS}"
echo "[OK] backup => ${F}.bak_pin_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path(".github/workflows/vsp_p0_commercial_gate.yml")
s=p.read_text(encoding="utf-8", errors="replace")

# Replace runs-on: self-hosted -> runs-on: [self-hosted, vsp-ui]
s2=re.sub(r'^\s*runs-on:\s*self-hosted\s*$',
          '    runs-on: [self-hosted, vsp-ui]', s, flags=re.M)

p.write_text(s2, encoding="utf-8")
print("[OK] pinned runs-on to [self-hosted, vsp-ui]")
PY
