#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p525_verify_release_and_customer_smoke_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p529_${TS}"
echo "[OK] backup => ${F}.bak_p529_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("bin/p525_verify_release_and_customer_smoke_v1.sh")
s=p.read_text(encoding="utf-8", errors="replace")

# replace grep block: grep -q "$x"  => grep -Fq "/$x"
s2=re.sub(r'grep -q "\$x"', r'grep -Fq "/$x"', s)
p.write_text(s2, encoding="utf-8")
print("[OK] patched P525 to grep -Fq '/$x'")
PY

bash -n "$F"
echo "[OK] bash -n passed"
