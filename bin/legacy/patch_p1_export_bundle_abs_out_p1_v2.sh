#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p1_export_bundle_by_rid_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_absout_${TS}"
echo "[BACKUP] ${F}.bak_absout_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("bin/p1_export_bundle_by_rid_v1.sh")
s = p.read_text(encoding="utf-8", errors="replace")
orig = s

# (1) OUT_DIR -> absolute (based on repo pwd)
if 'OUT_DIR="out_ci/bundles"' in s:
    s = s.replace('OUT_DIR="out_ci/bundles"', 'OUT_DIR="$(pwd)/out_ci/bundles"', 1)

# (2) tar target path: remove ../../ prefix (tar runs inside /tmp WORK)
# handle both "../../${BUNDLE}" and "../../$BUNDLE" just in case
s = s.replace('tar -czf "../../${BUNDLE}"', 'tar -czf "${BUNDLE}"')
s = s.replace('tar -czf "../../$BUNDLE"', 'tar -czf "$BUNDLE"')

if s == orig:
    print("[WARN] no changes applied (maybe already patched)")
else:
    p.write_text(s, encoding="utf-8")
    print("[OK] patched: OUT_DIR absolute + tar writes to ${BUNDLE} directly")
PY

bash -n "$F" >/dev/null
echo "[OK] bash -n OK: $F"
