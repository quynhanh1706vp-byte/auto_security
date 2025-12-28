#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

FILES=(
  "static/js/vsp_ui_loader_route.js"
  "static/js/vsp_dashboard_enhance_v1.js"
  "static/js/vsp_runs_tab_resolved_v1.js"
)

for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "[ERR] missing $f"; exit 2; }
  cp -f "$f" "$f.bak_dd_safe_${TS}" && echo "[BACKUP] $f.bak_dd_safe_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import re

def inject_safe_call(loader: Path):
    s = loader.read_text(encoding="utf-8", errors="ignore")
    if "__VSP_DD_SAFE_CALL__" in s:
        print("[OK] safe-call already in loader")
        return

    addon = r"""
/* __VSP_DD_SAFE_CALL__ (P0): call drilldown handler as fn OR {open: fn} */
(function(){
  'use strict';
  if (window.__VSP_DD_SAFE_CALL__) return;
  window.__VSP_DD_SAFE_CALL__ = function(handler){
    try{
      var args = Array.prototype.slice.call(arguments, 1);
      if (typeof handler === 'function') return handler.apply(null, args);
      if (handler && typeof handler.open === 'function') return handler.open.apply(handler, args);
    }catch(e){
      try{ console.warn('[VSP][DD_SAFE_CALL]', e); }catch(_){}
    }
    return null;
  };
})();
"""
    # best place: after first 'use strict' if present, else prepend
    m = re.search(r"(['\"])use strict\1\s*;?", s)
    if m:
        i = m.end()
        s2 = s[:i] + "\n" + addon + "\n" + s[i:]
    else:
        s2 = addon + "\n" + s
    loader.write_text(s2, encoding="utf-8")
    print("[OK] injected safe-call into loader")

def patch_callsites(p: Path):
    s = p.read_text(encoding="utf-8", errors="ignore")
    # replace direct call with safe call, keep args
    # VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(a,b) => window.__VSP_DD_SAFE_CALL__(window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2, a,b)
    pat = r"\bVSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\("
    rep = "window.__VSP_DD_SAFE_CALL__(window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2, "
    n = len(re.findall(pat, s))
    if n:
        s = re.sub(pat, rep, s)
        p.write_text(s, encoding="utf-8")
    print(f"[OK] patched {p} calls={n}")

inject_safe_call(Path("static/js/vsp_ui_loader_route.js"))
patch_callsites(Path("static/js/vsp_dashboard_enhance_v1.js"))
patch_callsites(Path("static/js/vsp_runs_tab_resolved_v1.js"))
PY

node --check static/js/vsp_ui_loader_route.js >/dev/null && echo "[OK] node --check loader OK"
node --check static/js/vsp_dashboard_enhance_v1.js >/dev/null && echo "[OK] node --check dashboard_enhance OK"
node --check static/js/vsp_runs_tab_resolved_v1.js >/dev/null && echo "[OK] node --check runs_tab OK"

echo "[OK] patch done"
