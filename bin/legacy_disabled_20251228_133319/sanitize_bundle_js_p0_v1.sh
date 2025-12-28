#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_sanitize_${TS}"
echo "[BACKUP] ${F}.bak_sanitize_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_commercial_v1.js")
b = p.read_bytes()

# Remove UTF-8 BOM
if b.startswith(b'\xef\xbb\xbf'):
    b = b[3:]

# Replace NBSP (U+00A0) with space
b = b.replace(b'\xc2\xa0', b' ')

# Replace U+2028/U+2029 with newline
b = b.replace(b'\xe2\x80\xa8', b'\n').replace(b'\xe2\x80\xa9', b'\n')

# Normalize CRLF -> LF
b = b.replace(b'\r\n', b'\n').replace(b'\r', b'\n')

# Drop other ASCII control chars except \n \t
clean = bytearray()
for x in b:
    if x in (9,10) or x >= 32:
        clean.append(x)
# ensure trailing newline
if not clean.endswith(b'\n'):
    clean += b'\n'

p.write_bytes(bytes(clean))
print("[OK] sanitized:", p, "bytes=", len(clean))
PY

echo "== node check =="
node --check static/js/vsp_bundle_commercial_v1.js
echo "[OK] node --check PASS"
