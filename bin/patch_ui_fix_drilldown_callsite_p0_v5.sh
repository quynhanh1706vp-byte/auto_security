#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_FIX_DRILLDOWN_CALLSITE_P0_V5"

echo "== find callsites by NAME (exclude backups) =="
mapfile -t FILES < <(
  grep -RIl --exclude='*.bak*' --exclude='*bak_*' --exclude='*._bak_*' \
    "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2" static/js templates 2>/dev/null | sort -u
)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "[ERR] cannot find symbol in static/js or templates"
  echo "Hint: maybe file name differs; show loaded scripts:"
  grep -RIn "vsp_dashboard_.*\\.js" templates/vsp_dashboard_2025.html | head -n 50 || true
  exit 2
fi

printf "[OK] patching %s file(s)\n" "${#FILES[@]}"
printf " - %s\n" "${FILES[@]}"

for F in "${FILES[@]}"; do
  [ -f "$F" ] || continue
  cp -f "$F" "$F.bak_${MARK}_${TS}" && echo "[BACKUP] $F.bak_${MARK}_${TS}"

  python3 - "$F" "$MARK" <<'PY'
from pathlib import Path
import re, sys
p = Path(sys.argv[1]); mark=sys.argv[2]
s = p.read_text(encoding="utf-8", errors="replace")
if mark in s:
    print("[OK] already:", p); raise SystemExit(0)

helper = f"""
/* {mark}: safe-call drilldown artifacts (function OR object.open) */
function __VSP_DD_ART_CALL__(h, ...args) {{
  try {{
    if (typeof h === 'function') return h(...args);
    if (h && typeof h.open === 'function') return h.open(...args);
  }} catch(e) {{ try{{console.warn('[VSP][DD_SAFE]', e);}}catch(_e){{}} }}
  return null;
}}
"""

# inject helper near top
m = re.search(r"['\"]use strict['\"]\s*;\s*", s)
if m:
    s = s[:m.end()] + "\n" + helper + "\n" + s[m.end():]
else:
    s = helper + "\n" + s

# Replace callsites, tolerant to newline before '('
# VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(  --> __VSP_DD_ART_CALL__(VSP_DASH..., 
s = re.sub(r"\bVSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(",
           "__VSP_DD_ART_CALL__(VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2, ",
           s)

p.write_text(s, encoding="utf-8")
print("[OK] patched:", p)
PY

  # node --check only for real .js files (avoid .html/.bak issues)
  if [[ "$F" == *.js ]]; then
    node --check "$F" >/dev/null && echo "[OK] node --check $F"
  fi
done

echo "DONE. Ctrl+Shift+R rồi mở #dashboard."
