#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && NODE_OK=1 || NODE_OK=0
command -v systemctl >/dev/null 2>&1 && SYS_OK=1 || SYS_OK=0

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
MARK="VSP_P1_DASH_DISABLE_LEGACY_TICK_V1B_FIX"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_disable_tick_${TS}"
echo "[BACKUP] ${JS}.bak_disable_tick_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_luxe_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P1_DASH_DISABLE_LEGACY_TICK_V1B_FIX"

changed = 0

# (1) Disable legacy tick: setInterval(tick, 12000);
pat = r'^\s*setInterval\s*\(\s*tick\s*,\s*12000\s*\)\s*;\s*$'
s2, n = re.subn(pat, f'  /* {mark}: disabled legacy tick(12000) to prevent UI freeze */', s, flags=re.M)
if n:
    s = s2
    changed += n

# (2) Clamp findings_unified fetches lacking limit -> add &limit=25
# Handles both "...path=findings_unified.json" and template literals.
# Only adds if "limit=" is not present nearby (simple heuristic).
def clamp_findings(m):
    frag = m.group(0)
    # if already has limit, keep
    if "limit=" in frag:
        return frag
    # add &limit=25 after findings_unified.json
    return frag.replace("findings_unified.json", "findings_unified.json&limit=25")

s2, n = re.subn(r'findings_unified\.json(?![^\\n]{0,140}limit=)', clamp_findings, s)
if n:
    s = s2
    changed += n

# (3) (Optional harden) If there is a direct "path=findings_unified.json" in URLSearchParams without limit
s2, n = re.subn(r'(path=findings_unified\.json)(?![^\\n]{0,140}limit=)', r'\1&limit=25', s)
if n:
    s = s2
    changed += n

if changed == 0 and mark in s:
    print("[OK] already patched:", mark)
elif changed == 0:
    print("[WARN] no matching legacy tick / findings_unified patterns found; file may differ.")
else:
    # Add marker near top once
    if mark not in s:
        s = f"/* {mark} */\n" + s
    p.write_text(s, encoding="utf-8")
    print("[OK] patched:", mark, "changed=", changed)
PY

if [ "$NODE_OK" = "1" ]; then
  node --check "$JS" >/dev/null && echo "[OK] node --check ok: $JS" || { echo "[ERR] node --check failed: $JS"; exit 3; }
fi

if [ "$SYS_OK" = "1" ]; then
  systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted: $SVC" || echo "[WARN] restart skipped/failed: $SVC"
fi

echo "[DONE] legacy tick disabled + findings_unified clamped (no format-string bug)."
