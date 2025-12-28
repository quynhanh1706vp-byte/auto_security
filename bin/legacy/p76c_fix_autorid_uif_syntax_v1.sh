#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_tabs4_autorid_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p76c_${TS}"
echo "[OK] backup ${F}.bak_p76c_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_tabs4_autorid_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
orig=s

# Fix common bad token: "uif(__VSP_DEBUG_P76) .searchParams.set("
s = re.sub(r'\buif\s*\(\s*__VSP_DEBUG_P76\s*\)\s*\.\s*searchParams\.set\s*\(',
           r'if(__VSP_DEBUG_P76) u.searchParams.set(',
           s)

# Fix variant: "uif(__VSP_DEBUG_P76) .searchParams.set("_autorid_p63","1");"
s = re.sub(r'\buif\s*\(\s*__VSP_DEBUG_P76\s*\)\s*\.\s*searchParams\.set\(',
           r'if(__VSP_DEBUG_P76) u.searchParams.set(',
           s)

# If someone wrote "if(__VSP_DEBUG_P76) .searchParams.set(" -> also fix
s = re.sub(r'\bif\s*\(\s*__VSP_DEBUG_P76\s*\)\s*\.\s*searchParams\.set\(',
           r'if(__VSP_DEBUG_P76) u.searchParams.set(',
           s)

if s == orig:
    print("[WARN] no uif pattern found (maybe already clean).")
else:
    p.write_text(s, encoding="utf-8")
    print("[OK] fixed autorid syntax (uif -> if u.searchParams.set)")
PY

if command -v node >/dev/null 2>&1; then
  node -c "$F" >/dev/null 2>&1 && echo "[OK] node -c syntax OK" || { echo "[ERR] JS syntax FAIL"; exit 2; }
fi

echo "[DONE] P76C applied. Hard refresh: Ctrl+Shift+R"
