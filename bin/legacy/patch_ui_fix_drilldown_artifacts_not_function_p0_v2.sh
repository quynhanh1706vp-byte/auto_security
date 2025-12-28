#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_FIX_DRILLDOWN_ARTIFACTS_NOT_FUNCTION_P0_V2"

echo "== find offenders =="
mapfile -t FILES < <(
  grep -RIl --exclude-dir='snapshots' --exclude-dir='node_modules' \
    "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2" static/js 2>/dev/null || true
)

# Fallback: include likely loader/dashboard files even if string is not found due to minify
if [ "${#FILES[@]}" -eq 0 ]; then
  while IFS= read -r f; do FILES+=("$f"); done < <(find static/js -maxdepth 2 -type f -print | grep -E "loader_route|dashboard_enhanc" || true)
fi

[ "${#FILES[@]}" -gt 0 ] || { echo "[ERR] cannot find target JS under static/js"; exit 2; }

echo "[OK] target files:"
printf " - %s\n" "${FILES[@]}"

for F in "${FILES[@]}"; do
  [ -f "$F" ] || continue
  cp -f "$F" "$F.bak_${MARK}_${TS}" && echo "[BACKUP] $F.bak_${MARK}_${TS}"

  python3 - "$F" "$MARK" <<'PY'
from pathlib import Path
import sys, re

p = Path(sys.argv[1])
mark = sys.argv[2]
s = p.read_text(encoding="utf-8", errors="replace")

if mark in s:
    print("[OK] already patched:", p)
    raise SystemExit(0)

shim = f"""
/* {mark}
 * Fix: TypeError VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(...) is not a function
 * Normalize BEFORE first use:
 *   - if function: keep
 *   - if object with .open(): wrap as function(arg)->obj.open(arg)
 *   - else: no-op (never throw)
 */
(function(){{
  'use strict';
  if (window.__{mark}) return;
  window.__{mark} = 1;

  function normalize(v){{
    if (typeof v === 'function') return v;
    if (v && typeof v.open === 'function') {{
      const obj = v;
      const fn = function(arg){{ try {{ return obj.open(arg); }} catch(e){{ console.warn('[VSP][DD_FIX] open() failed', e); return null; }} }};
      fn.__wrapped_from_object = true;
      return fn;
    }}
    const noop = function(_arg){{ return null; }};
    noop.__noop = true;
    return noop;
  }}

  try {{
    // trap future assignments
    let _val = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;
    Object.defineProperty(window, 'VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2', {{
      configurable: true, enumerable: true,
      get: function(){{ return _val; }},
      set: function(v){{ _val = normalize(v); }}
    }});
    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = _val;
  }} catch(e) {{
    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = normalize(window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2);
  }}
}})();
"""

# Insert shim BEFORE first usage of the symbol if possible; else after first 'use strict'
idx = s.find("VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2")
if idx != -1:
    # insert at line boundary before the first occurrence
    pre = s[:idx]
    # find nearest line start
    ls = pre.rfind("\n")
    insert_at = ls+1 if ls != -1 else 0

    # prefer to insert right after 'use strict' but still before first use
    # find last 'use strict' before insert_at
    m = None
    for mm in re.finditer(r"['\"]use strict['\"]\s*;\s*", s[:insert_at]):
        m = mm
    if m:
        insert_at = m.end()

    out = s[:insert_at] + "\n" + shim + "\n" + s[insert_at:]
else:
    # no occurrence found: just insert after first 'use strict' or prepend
    m = re.search(r"['\"]use strict['\"]\s*;\s*", s)
    if m:
        insert_at = m.end()
        out = s[:insert_at] + "\n" + shim + "\n" + s[insert_at:]
    else:
        out = shim + "\n" + s

p.write_text(out, encoding="utf-8")
print("[OK] injected shim into:", p)
PY

  node --check "$F" >/dev/null && echo "[OK] node --check $F"
done

echo
echo "DONE. Next:"
echo "  1) Ctrl+Shift+R"
echo "  2) mở lại #dashboard và #runs, bấm drilldown/artifacts"
echo "  3) console phải hết TypeError is not a function"
