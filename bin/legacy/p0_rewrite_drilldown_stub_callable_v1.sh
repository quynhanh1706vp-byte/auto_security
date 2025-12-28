#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

STUB="static/js/vsp_drilldown_stub_safe_v1.js"
[ -f "$STUB" ] || { echo "[ERR] missing $STUB"; ls -la static/js | sed -n '1,160p'; exit 2; }
cp -f "$STUB" "$STUB.bak_callable_${TS}" && echo "[BACKUP] $STUB.bak_callable_${TS}"

# 1) Rewrite stub to be ALWAYS callable (fn OR {open:fn}), with fallback navigation.
cat > "$STUB" <<'JS'
/* VSP_DRILLDOWN_STUB_SAFE_CALLABLE_V1 (commercial):
   - window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 is ALWAYS callable
   - accepts "real impl" via setter (function or object with .open/.run/.invoke)
   - fallback: emit intent + navigate #datasource */
(function(){
  'use strict';
  if (window.__VSP_DRILLDOWN_STUB_SAFE_CALLABLE_V1__) return;
  window.__VSP_DRILLDOWN_STUB_SAFE_CALLABLE_V1__ = 1;

  var _impl = null;

  function _emitIntent(intent){
    try{
      window.__VSP_DRILLDOWN_INTENT__ = intent;
      try{ localStorage.setItem('vsp_drilldown_intent_v1', JSON.stringify(intent)); }catch(_){}
      window.dispatchEvent(new CustomEvent('vsp:drilldown', { detail: intent }));
    }catch(_){}
  }

  function _gotoDataSource(){
    try{ if (window.location.hash !== '#datasource') window.location.hash = '#datasource'; }catch(_){}
  }

  function _safeInvoke(impl, args){
    try{
      if (typeof impl === 'function') return impl.apply(null, args);
      if (impl && typeof impl.open === 'function') return impl.open.apply(impl, args);
      if (impl && typeof impl.run === 'function') return impl.run.apply(impl, args);
      if (impl && typeof impl.invoke === 'function') return impl.invoke.apply(impl, args);
    }catch(e){
      try{ console.warn('[VSP][DD_SAFE_CALLABLE]', e); }catch(_){}
    }
    return null;
  }

  function exported(opts){
    var intent = {};
    try{
      if (typeof opts === 'string') intent.rid = opts;
      else if (opts && typeof opts === 'object') intent = opts;
      if (!intent.rid){
        intent.rid = (window.__VSP_RID_STATE__ && window.__VSP_RID_STATE__.rid) || window.__VSP_RID || null;
      }
      intent.ts = Date.now();
      intent.kind = intent.kind || 'artifacts';
    }catch(_){}

    var r = _safeInvoke(_impl, arguments);
    if (r !== null) return r;

    _emitIntent(intent);
    _gotoDataSource();
    try{
      if (typeof window.VSP_DATASOURCE_APPLY_DRILLDOWN_V1 === 'function'){
        return window.VSP_DATASOURCE_APPLY_DRILLDOWN_V1(intent);
      }
    }catch(_){}
    return null;
  }

  // Force callable getter/setter forever
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
    _impl = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;
    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = exported;
  }

  // Re-assert callable if clobbered later
  setInterval(function(){
    try{
      if (window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== exported){
        _impl = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;
        window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = exported;
      }
    }catch(_){}
  }, 800);
})();
JS

node --check "$STUB" >/dev/null && echo "[OK] node --check OK: $STUB"

# 2) Bump all references to stub with new ?v=TS (templates + static js)
python3 - <<PY
from pathlib import Path
import re
TS="${TS}"
pat = re.compile(r"(vsp_drilldown_stub_safe_v1\.js)(\?v=\d+)?")
roots = [Path("templates"), Path("static/js")]
changed=0
for root in roots:
    if not root.exists(): 
        continue
    for p in root.rglob("*"):
        if not p.is_file(): 
            continue
        if p.suffix not in (".html",".js"):
            continue
        s = p.read_text(encoding="utf-8", errors="ignore")
        if "vsp_drilldown_stub_safe_v1.js" not in s:
            continue
        b = p.with_suffix(p.suffix + f".bak_ddv_{TS}")
        b.write_text(s, encoding="utf-8")
        s2 = pat.sub(rf"\1?v={TS}", s)
        p.write_text(s2, encoding="utf-8")
        changed += 1
        print("[OK] bumped stub ?v=TS in", p)
print("[OK] bump done files_changed=", changed)
PY

# 3) Force callsites to use window.<fn> (avoid local shadowing)
python3 - <<'PY'
from pathlib import Path
import re

def patch(path):
    p = Path(path)
    if not p.exists(): 
        return
    s = p.read_text(encoding="utf-8", errors="ignore")
    pat = r"(?<![\w\.])VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\("
    n = len(re.findall(pat, s))
    if n:
        b = p.with_suffix(p.suffix + ".bak_scopefix_v1")
        b.write_text(s, encoding="utf-8")
        s = re.sub(pat, "window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(", s)
        p.write_text(s, encoding="utf-8")
        print("[OK] scope-fixed", p, "calls=", n)

patch("static/js/vsp_dashboard_enhance_v1.js")
patch("static/js/vsp_runs_tab_resolved_v1.js")
PY

echo "[OK] P0 rewrite stub callable done"
