#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_FIX_DRILLDOWN_EVERYWHERE_P0_V4"

echo "== locate callsites (exclude backups) =="
mapfile -t JSFILES < <(
  grep -RIn --exclude='*.bak*' --exclude='*bak_*' --exclude='*._bak_*' \
    "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(" static/js 2>/dev/null | cut -d: -f1 | sort -u
)
mapfile -t TPLFILES < <(
  grep -RIn --exclude='*.bak*' --exclude='*bak_*' \
    "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(" templates 2>/dev/null | cut -d: -f1 | sort -u || true
)

printf "[JS] %s file(s)\n" "${#JSFILES[@]}"
printf " - %s\n" "${JSFILES[@]:-}"
printf "[TPL] %s file(s)\n" "${#TPLFILES[@]}"
printf " - %s\n" "${TPLFILES[@]:-}"

patch_one() {
  local F="$1"
  [ -f "$F" ] || return 0
  cp -f "$F" "$F.bak_${MARK}_${TS}" && echo "[BACKUP] $F.bak_${MARK}_${TS}"

  python3 - "$F" "$MARK" <<'PY'
from pathlib import Path
import re, sys
p = Path(sys.argv[1]); mark=sys.argv[2]
s = p.read_text(encoding="utf-8", errors="replace")
if mark in s:
    print("[OK] already:", p); raise SystemExit(0)

helper = f"""
/* {mark}: safe-call drilldown artifacts */
function __VSP_DD_ART_CALL__(h, ...args) {{
  try {{
    if (typeof h === 'function') return h(...args);
    if (h && typeof h.open === 'function') return h.open(...args);
  }} catch(e) {{ try{{console.warn('[VSP][DD_SAFE]', e);}}catch(_e){{}} }}
  return null;
}}
"""

# inject helper near top: after use strict if possible
m = re.search(r"['\"]use strict['\"]\s*;\s*", s)
if m:
    s = s[:m.end()] + "\n" + helper + "\n" + s[m.end():]
else:
    s = helper + "\n" + s

# rewrite callsites
s = re.sub(r"\bVSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(",
           "__VSP_DD_ART_CALL__(VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2, ",
           s)

p.write_text(s, encoding="utf-8")
print("[OK] patched:", p)
PY
}

# Patch JS files
for f in "${JSFILES[@]}"; do patch_one "$f"; done

# Patch template files (inline JS)
for f in "${TPLFILES[@]}"; do patch_one "$f"; done

echo "== syntax check main JS only (ignore backups) =="
for f in "${JSFILES[@]}"; do
  node --check "$f" >/dev/null && echo "[OK] node --check $f"
done

echo
echo "DONE. Ctrl+Shift+R rồi mở #dashboard. Nếu còn lỗi, chụp lại console + dòng script file đang throw."
