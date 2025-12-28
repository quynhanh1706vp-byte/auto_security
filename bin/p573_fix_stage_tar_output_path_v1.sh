#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="official/pack_release.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p573_${TS}"
echo "[OK] backup => ${F}.bak_p573_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("official/pack_release.sh")
s = p.read_text(encoding="utf-8", errors="replace")

# Replace: ( cd "$STAGE" && tar -czf "$TGZ" . )
# with:    tar -C "$STAGE" -czf "$TGZ" .
pat = r'\(\s*cd\s+"\$STAGE"\s*&&\s*tar\s+-czf\s+"\$TGZ"\s+\.\s*\)'
if re.search(pat, s):
    s2 = re.sub(pat, 'tar -C "$STAGE" -czf "$TGZ" .', s, count=1)
else:
    # Fallback: if they wrote in slightly different form
    pat2 = r'cd\s+"\$STAGE"\s*&&\s*tar\s+-czf\s+"\$TGZ"\s+\.\s*'
    if re.search(pat2, s):
        s2 = re.sub(pat2, 'tar -C "$STAGE" -czf "$TGZ" .\n', s, count=1)
    else:
        raise SystemExit("[ERR] cannot find stage tar line to patch")

p.write_text(s2, encoding="utf-8")
print("[OK] patched stage tar output path (use -C instead of cd)")
PY

bash -n official/pack_release.sh
echo "[OK] bash -n ok"

# ensure bin/pack_release.sh points to official
ln -sf ../official/pack_release.sh bin/pack_release.sh
chmod +x official/pack_release.sh
echo "[OK] linked bin/pack_release.sh -> official/pack_release.sh"
