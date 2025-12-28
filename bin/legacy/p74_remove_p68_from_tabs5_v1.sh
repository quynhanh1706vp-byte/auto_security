#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p74_${TS}"
echo "[OK] backup ${F}.bak_p74_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

# Remove the P68 block by marker
before=s
s=re.sub(r'(?s)/\*\s*VSP_P68_FORCE_LOAD_LUXE_V1.*?\*/\s*\(function\(\)\{.*?\}\)\(\);\s*', '', s)

if s == before:
    print("[WARN] P68 marker block not found (maybe already removed).")
else:
    print("[OK] removed P68 block")

# Sanity: ensure P72B still present
if "VSP_P72B_LOAD_DASHBOARD_MAIN_V1" not in s:
    print("[ERR] P72B marker missing after edit (abort)")
    raise SystemExit(2)

p.write_text(s, encoding="utf-8")
print("[OK] wrote tabs5 without P68 (kept P72B)")
PY

if command -v node >/dev/null 2>&1; then
  node -c "$F" >/dev/null 2>&1 && echo "[OK] node -c syntax OK" || { echo "[ERR] JS syntax fail"; exit 2; }
fi

echo "[DONE] P74 applied. Hard refresh: Ctrl+Shift+R"
