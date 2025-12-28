#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/patch_vsp4_ui_topbar_quickactions_p8_v3.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_basefix_${TS}"
echo "[BACKUP] $F.bak_basefix_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("bin/patch_vsp4_ui_topbar_quickactions_p8_v3.sh")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_TOPBAR_BASE_UNBOUND_FIX_P0_V1"
if MARK in s:
    print("[OK] already patched:", MARK); raise SystemExit(0)

lines=s.splitlines(True)

# find first cd /home/test/Data/SECURITY_BUNDLE/ui or after set -euo pipefail
ins = None
for i,l in enumerate(lines):
    if "set -euo pipefail" in l:
        ins = i+1
        break
if ins is None:
    ins = 0

inject = [
    "\n# "+MARK+"\n",
    'BASE="${BASE:-http://127.0.0.1:8910}"\n'
]

# avoid duplicate BASE assignment
if any(l.startswith('BASE="${BASE:-') for l in lines):
    print("[OK] BASE default already exists; only mark")
    inject = ["\n# "+MARK+"\n"]

lines[ins:ins] = inject
p.write_text("".join(lines), encoding="utf-8")
print("[OK] patched:", MARK)
PY

echo "== bash -n =="
bash -n "$F"
echo "[OK] base unbound fixed"
