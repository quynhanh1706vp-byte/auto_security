#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

TPL="templates/vsp_dashboard_2025.html"
JS="static/js/vsp_ui_global_shims_commercial_p0_v1.js"

[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 3; }

cp -f "$TPL" "$TPL.bak_dd_textleak_${TS}" && echo "[BACKUP] $TPL.bak_dd_textleak_${TS}"
cp -f "$JS"  "$JS.bak_dd_alias_${TS}"     && echo "[BACKUP] $JS.bak_dd_alias_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

tpl = Path("templates/vsp_dashboard_2025.html")
s = tpl.read_text(encoding="utf-8", errors="ignore")

# (1) Remove leaked inline code line if it appears as plain text in HTML
# Only remove the line containing the marker; do NOT touch RID lines etc.
lines = s.splitlines(True)
out = []
removed = 0
for ln in lines:
    if "VSP_FIX_DRILLDOWN_CALLSITE_P0_V5" in ln:
        removed += 1
        continue
    out.append(ln)
if removed:
    tpl.write_text("".join(out), encoding="utf-8")
print(f"[OK] template cleaned leaked_line_removed={removed}")

# (2) Add robust drilldown alias shim into global shims (so callers can keep calling as function)
js = Path("static/js/vsp_ui_global_shims_commercial_p0_v1.js")
j = js.read_text(encoding="utf-8", errors="ignore")

if "__VSP_FIX_DD_ALIAS_P0_V1" not in j:
    addon = r'''
/* __VSP_FIX_DD_ALIAS_P0_V1: make drilldown handler callable even if it is an object (.open) */
(function(){
  'use strict';
  if (window.__VSP_FIX_DD_ALIAS_P0_V1) return;
  window.__VSP_FIX_DD_ALIAS_P0_V1 = 1;

  // Safe call: function OR {open: fn}
  window.__VSP_DD_ART_CALL__ = window.__VSP_DD_ART_CALL__ || function(h){
    try{
      var args = Array.prototype.slice.call(arguments, 1);
      if (typeof h === 'function') return h.apply(null, args);
      if (h && typeof h.open === 'function') return h.open.apply(h, args);
    }catch(e){
      try{ console.warn('[VSP][DD_SAFE]', e); }catch(_){}
    }
    return null;
  };

  // If VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 is NOT a function but exists, wrap it
  try{
    var h = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;
    if (h && typeof h !== 'function'){
      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){
        return window.__VSP_DD_ART_CALL__.apply(null, [h].concat([].slice.call(arguments)));
      };
      try{ console.log('[VSP][P0] drilldown alias wrapped (obj->fn)'); }catch(_){}
    }
    // If missing entirely, provide a harmless no-op function (avoid hard crash)
    if (!window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2){
      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){
        try{ console.warn('[VSP][P0] drilldown handler missing; noop'); }catch(_){}
        return null;
      };
    }
  }catch(e){
    try{ console.warn('[VSP][P0] drilldown alias init failed', e); }catch(_){}
  }
})();
'''
    js.write_text(j.rstrip() + "\n" + addon + "\n", encoding="utf-8")
    print("[OK] appended __VSP_FIX_DD_ALIAS_P0_V1 to global shims")
else:
    print("[OK] __VSP_FIX_DD_ALIAS_P0_V1 already present; skip")
PY

node --check "$JS" >/dev/null && echo "[OK] node --check OK: $JS"
echo "[OK] patch done"
