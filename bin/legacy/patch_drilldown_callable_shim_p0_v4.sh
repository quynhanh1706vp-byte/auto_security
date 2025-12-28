#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_drilldown_stub_safe_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; ls -la static/js | sed -n '1,120p'; exit 2; }

cp -f "$F" "$F.bak_dd_callable_${TS}" && echo "[BACKUP] $F.bak_dd_callable_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_drilldown_stub_safe_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")

marker = "VSP_DD_CALLABLE_SHIM_P0_V4"
if marker in s:
    print("[OK] shim already present")
    raise SystemExit(0)

shim = r"""/* VSP_DD_CALLABLE_SHIM_P0_V4: force VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 to be callable */
(function(){
  'use strict';
  if (window.__VSP_DD_CALLABLE_SHIM_P0_V4__) return;
  window.__VSP_DD_CALLABLE_SHIM_P0_V4__ = 1;

  var _impl = null;

  function _safeInvoke(impl, args){
    try{
      if (typeof impl === 'function') return impl.apply(null, args);
      if (impl && typeof impl.open === 'function') return impl.open.apply(impl, args);
      if (impl && typeof impl.run === 'function') return impl.run.apply(impl, args);
      if (impl && typeof impl.invoke === 'function') return impl.invoke.apply(impl, args);
      return null;
    }catch(e){
      try{ console.warn('[VSP][DD] invoke failed', e); }catch(_){}
      return null;
    }
  }

  function exported(){
    return _safeInvoke(_impl, arguments);
  }

  function install(){
    try{
      if (window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 && window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== exported){
        _impl = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;
      }
      Object.defineProperty(window, 'VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2', {
        configurable: true,
        enumerable: true,
        get: function(){ return exported; },
        set: function(v){
          _impl = v;
          try{ console.log('[VSP][DD] accepted real impl'); }catch(_){}
        }
      });
    }catch(e){
      // fallback: best-effort
      _impl = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;
      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = exported;
    }
  }

  install();

  // Re-assert callable if clobbered later
  setInterval(function(){
    try{
      if (window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== exported){
        _impl = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;
        window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = exported;
      }
    }catch(_){}
  }, 1000);
})();
"""
p.write_text(shim + "\n\n" + s, encoding="utf-8")
print("[OK] prepended callable shim to", p)
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK"
echo "[OK] done"
