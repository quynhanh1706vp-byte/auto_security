#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p58a1_${TS}"
echo "[OK] backup ${F}.bak_p58a1_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_bundle_commercial_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

orig=s

# Fix array element written as object field:  , trace:"TRACE"  or trace:'TRACE'
# Common forms:
#   [..., trace:"TRACE"]
#   [..., trace:"TRACE", ...]
#   [trace:"TRACE", ...]
s = re.sub(r'\[\s*trace\s*:\s*("TRACE"|\'TRACE\')\s*,', r'["TRACE",', s)
s = re.sub(r',\s*trace\s*:\s*("TRACE"|\'TRACE\')\s*,', r', "TRACE",', s)
s = re.sub(r',\s*trace\s*:\s*("TRACE"|\'TRACE\')\s*\]', r', "TRACE"]', s)

if s != orig:
    p.write_text(s, encoding="utf-8")
    print("[PATCHED] fixed trace:\"TRACE\" inside arrays")
else:
    print("[NOCHANGE] pattern not found (maybe already fixed?)")
PY

echo "== node --check $F =="
node --check "$F"
echo "[PASS] bundle v1 syntax OK"
