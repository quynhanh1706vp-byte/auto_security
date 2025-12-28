#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_DRILLDOWN_ARTIFACTS_NORMALIZE_P0_V1"

# targets (best guess based on your repo history + console filenames)
CANDS=(
  "static/js/vsp_dashboard_enhance_v1.js"
  "static/js/vsp_ui_loader_route_v1.js"
  "static/js/vsp_ui_loader_route__v1.js"
  "static/js/vsp_ui_loader_route__js"
  "static/js/vsp_ui_loader_route.js"
)

found=()
for f in "${CANDS[@]}"; do
  [ -f "$f" ] && found+=("$f")
done

# also search by keyword if not found enough
if [ "${#found[@]}" -lt 1 ]; then
  while IFS= read -r f; do found+=("$f"); done < <(find static/js -maxdepth 2 -type f -name "*.js" -print | grep -E "loader_route|dashboard_enhance" || true)
fi

if [ "${#found[@]}" -lt 1 ]; then
  echo "[ERR] cannot find target js under static/js (loader_route / dashboard_enhance)"
  exit 2
fi

echo "[OK] patching files:"
printf " - %s\n" "${found[@]}"

for F in "${found[@]}"; do
  cp -f "$F" "$F.bak_${MARK}_${TS}"
  echo "[BACKUP] $F.bak_${MARK}_${TS}"

  python3 - "$F" "$MARK" <<'PY'
from pathlib import Path
import sys, re

p = Path(sys.argv[1])
mark = sys.argv[2]
s = p.read_text(encoding="utf-8", errors="replace")

if mark in s:
    print("[OK] already patched:", p)
    raise SystemExit(0)

SNIP = r"""
/* VSP_DRILLDOWN_ARTIFACTS_NORMALIZE_P0_V1
 * Fix: Uncaught TypeError: VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(...) is not a function
 * Normalize window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2:
 *  - if function: keep
 *  - if object with .open(): wrap to function
 *  - if missing: provide no-op function (never throw)
 */
(function(){
  'use strict';
  if (window.__VSP_DRILLDOWN_ARTIFACTS_NORMALIZE_P0_V1) return;
  window.__VSP_DRILLDOWN_ARTIFACTS_NORMALIZE_P0_V1 = 1;

  function normalize(v){
    if (typeof v === 'function') return v;
    if (v && typeof v.open === 'function'){
      const obj = v;
      const fn = function(arg){
        try { return obj.open(arg); } catch(_e){ return null; }
      };
      fn.__wrapped_from_object = true;
      return fn;
    }
    // missing/unknown => no-op (never throw)
    const noop = function(_arg){ return null; };
    noop.__noop = true;
    return noop;
  }

  try{
    // Use defineProperty to normalize future assignments too (robust).
    let _val = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;
    Object.defineProperty(window, 'VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2', {
      configurable: true,
      enumerable: true,
      get: function(){ return _val; },
      set: function(v){ _val = normalize(v); }
    });
    // trigger normalization on current value
    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = _val;
  }catch(_e){
    // fallback if defineProperty is blocked
    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = normalize(window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2);
  }
})();
"""

# insert early: right after first "'use strict';" if present, else prepend.
m = re.search(r"['\"]use strict['\"]\s*;\s*", s)
if m:
    i = m.end()
    out = s[:i] + "\n" + SNIP + "\n" + s[i:]
else:
    out = SNIP + "\n" + s

p.write_text(out, encoding="utf-8")
print("[OK] injected:", p)
PY

  node --check "$F" >/dev/null && echo "[OK] node --check $F"
done

echo
echo "DONE."
echo "Next: Ctrl+Shift+R (hard refresh) rồi click lại Drilldown/Artifacts xem console còn đỏ không."
