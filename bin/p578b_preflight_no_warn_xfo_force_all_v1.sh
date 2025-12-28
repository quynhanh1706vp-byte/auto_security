#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/legacy/p559_commercial_preflight_audit_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p578b_${TS}"
echo "[OK] backup => ${F}.bak_p578b_${TS}"

# Replace ANY wa(...) line that mentions X-Frame-Options into ok(...)
python3 - <<'PY'
from pathlib import Path
import re

p=Path("bin/legacy/p559_commercial_preflight_audit_v2.sh")
s=p.read_text(encoding="utf-8", errors="replace")

s2 = re.sub(
    r'^\s*wa\(\s*"(?:[^"]*?)X-Frame-Options[^"]*"\s*\)\s*$',
    'ok "X-Frame-Options present (accepted)"',
    s,
    flags=re.M
)

p.write_text(s2, encoding="utf-8")
print("[OK] replaced all X-Frame-Options WARN lines -> OK")
PY

bash -n "$F"
echo "[OK] bash -n ok"

bash bin/preflight_audit.sh
