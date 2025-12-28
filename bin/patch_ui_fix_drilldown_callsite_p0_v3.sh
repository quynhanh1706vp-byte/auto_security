#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_FIX_DRILLDOWN_CALLSITE_P0_V3"
echo "== find call sites =="
mapfile -t FILES < <(grep -RIl --exclude-dir='node_modules' --exclude-dir='snapshots' \
  "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(" static/js 2>/dev/null || true)

[ "${#FILES[@]}" -gt 0 ] || { echo "[ERR] no call sites found under static/js"; exit 2; }

printf "[OK] will patch %s file(s)\n" "${#FILES[@]}"
printf " - %s\n" "${FILES[@]}"

for F in "${FILES[@]}"; do
  [ -f "$F" ] || continue
  cp -f "$F" "$F.bak_${MARK}_${TS}" && echo "[BACKUP] $F.bak_${MARK}_${TS}"

  python3 - "$F" "$MARK" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
mark = sys.argv[2]
s = p.read_text(encoding="utf-8", errors="replace")

if mark in s:
    print("[OK] already patched:", p)
    raise SystemExit(0)

helper = f"""
/* {mark}: safe-call for drilldown artifacts (function OR object.open) */
function __VSP_DD_ART_CALL__(h, ...args) {{
  try {{
    if (typeof h === 'function') return h(...args);
    if (h && typeof h.open === 'function') return h.open(...args);
  }} catch (e) {{
    try {{ console.warn('[VSP][DD_SAFE] call failed', e); }} catch (_e) {{}}
  }}
  return null;
}}
"""

# inject helper right after first "use strict"; else at top
m = re.search(r"['\"]use strict['\"]\s*;\s*", s)
if m:
    ins = m.end()
    s = s[:ins] + "\n" + helper + "\n" + s[ins:]
else:
    s = helper + "\n" + s

# replace call pattern (avoid double patch)
s = re.sub(
    r"\bVSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(",
    "__VSP_DD_ART_CALL__(VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2, ",
    s
)

p.write_text(s, encoding="utf-8")
print("[OK] patched:", p)
PY

  node --check "$F" >/dev/null && echo "[OK] node --check $F"
done

echo
echo "DONE. Now Ctrl+Shift+R and re-open #dashboard. The 'is not a function' must be gone."
