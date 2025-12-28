#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p0_freeze_ui_golden_baseline_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fixfind_${TS}"
echo "[BACKUP] ${F}.bak_fixfind_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("bin/p0_freeze_ui_golden_baseline_v1.sh")
s=p.read_text(encoding="utf-8", errors="replace")

# fix find ordering: find . -type f -maxdepth 3  => find . -maxdepth 3 -type f
s2=s.replace('find . -type f -maxdepth 3 -print0', 'find . -maxdepth 3 -type f -print0')

# add sha256 for the tgz (idempotent add)
if 'sha256sum "$PKG" > "$PKG.sha256"' not in s2:
    marker='echo "[OK] GOLDEN packed: $PKG"\n'
    if marker in s2:
        s2=s2.replace(marker, marker + 'sha256sum "$PKG" > "$PKG.sha256"\n' + 'echo "[OK] GOLDEN sha256: $PKG.sha256"\n')
    else:
        s2 += '\nsha256sum "$PKG" > "$PKG.sha256"\necho "[OK] GOLDEN sha256: $PKG.sha256"\n'

p.write_text(s2, encoding="utf-8")
print("[OK] patched", p)
PY

bash -n "$F"
echo "[OK] bash -n OK"

bash "$F"
