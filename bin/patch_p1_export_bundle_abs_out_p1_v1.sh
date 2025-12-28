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
import re

p = Path("bin/p1_export_bundle_by_rid_v1.sh")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) OUT_DIR relative -> absolute (based on repo pwd)
s2 = re.sub(
    r'OUT_DIR="out_ci/bundles"\nmkdir -p "\$\{OUT_DIR\}"',
    'OUT_DIR="$(pwd)/out_ci/bundles"\nmkdir -p "${OUT_DIR}"',
    s,
    count=1
)

# 2) tar output path: remove ../../ and write directly to absolute BUNDLE
s2 = re.sub(
    r'BUNDLE="\$\{OUT_DIR\}/\$\{RID\}\.bundle\.\$\{TS\}\.tgz"\n\(\n  cd "\$\{WORK\}"\n  # Pack relative paths without leading \./\n  tar -czf "\.\./\.\./\$\{BUNDLE\}" \\',
    'BUNDLE="${OUT_DIR}/${RID}.bundle.${TS}.tgz"\n(\n  cd "${WORK}"\n  # Pack directly to absolute bundle path\n  tar -czf "${BUNDLE}" \\',
    s2,
    count=1
)

if s2 == s:
    raise SystemExit("[ERR] patch did not apply (pattern mismatch)")

p.write_text(s2, encoding="utf-8")
print("[OK] patched output path to absolute OUT_DIR and fixed tar -czf target")
PY

bash -n "$F" >/dev/null
echo "[OK] bash -n OK: $F"
