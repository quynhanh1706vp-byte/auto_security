#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# (A) CLEAN TEXT LEAK in templates: remove any leaked code lines
echo "== clean template text leaks =="
for pat in "VSP_FIX_DRILLDOWN_CALLSITE" "__VSP_DD_ART_CALL__" "function __VSP_DD_ART_CALL__" "DD_SAFE_CALL"; do
  hits="$(grep -RIl "$pat" templates 2>/dev/null || true)"
  if [ -n "${hits:-}" ]; then
    while read -r f; do
      [ -f "$f" ] || continue
      cp -f "$f" "$f.bak_leakfix_${TS}"
      python3 - <<PY
from pathlib import Path
p=Path("$f")
s=p.read_text(encoding="utf-8", errors="ignore").splitlines(True)
out=[]
rm=0
for ln in s:
    if "$pat" in ln:
        rm+=1
        continue
    out.append(ln)
p.write_text("".join(out), encoding="utf-8")
print("[OK] cleaned", p, "removed_lines", rm)
PY
    done <<<"$hits"
  fi
done

# (B) WRITE a brand-new commercial drilldown implementation
echo "== write commercial drilldown impl =="
IMPL="static/js/vsp_drilldown_artifacts_impl_commercial_v1.js"
mkdir -p static/js
cp -f "$IMPL" "$IMPL.bak_${TS}" 2>/dev/null || true

cat > "$IMPL" <<'JS'
/* VSP_DRILLDOWN_ARTIFACTS_IMPL_COMMERCIAL_V1
   Goal: VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 is ALWAYS callable (even if someone sets object).
   Behavior: navigate to Data Source tab and pass drilldown intent (rid + optional filters). */
(function(){
  'use strict';
  if (window.__VSP_DRILLDOWN_ART_IMPL_COMMERCIAL_V1__) return;
  window.__VSP_DRILLDOWN_ART_IMPL_COMMERCIAL_V1__ = 1;

  var _impl = null;

  function _emitIntent(intent){
    try{
      // store intent for datasource tab to pick up
      window.__VSP_DRILLDOWN_INTENT__ = intent;
      try{ localStorage.setItem('vsp_drilldown_intent_v1', JSON.stringify(intent)); }catch(_){}
      window.dispatchEvent(new CustomEvent('vsp:drilldown', { detail: intent }));
    }catch(_){}
  }

  function _gotoDataSource(){
    try{
      // prefer router if exists
      if (window.location.hash !== '#datasource'){
        window.location.hash = '#datasource';
      }
    }catch(_){}
  }

  function _safeInvoke(impl, args){
    try{
      if (typeof impl === 'function') return impl.apply(null, args);
      if (impl && typeof impl.open === 'function') return impl.open.apply(impl, args);
      if (impl && typeof impl.run === 'function') return impl.run.apply(impl, args);
      if (impl && typeof impl.invoke === 'function') return impl.invoke.apply(impl, args);
    }catch(e){
      try{ console.warn('[VSP][DD] invoke failed', e); }catch(_){}
    }
    return null;
  }

  // exported callable used by dashboard/runs
  function exported(opts){
    // opts can be (rid) or ({rid, kind, severity, cwe, tool, ...})
    var intent = {};
    try{
      if (typeof opts === 'string') intent.rid = opts;
      else if (opts && typeof opts === 'object') intent = opts;
      // auto-fill rid from global state if missing
      if (!intent.rid){
        intent.rid = (window.__VSP_RID_STATE__ && window.__VSP_RID_STATE__.rid) || window.__VSP_RID || null;
      }
      intent.ts = Date.now();
      intent.kind = intent.kind || 'artifacts';
    }catch(_){}

    // If there is a real impl, call it. Otherwise do commercial fallback navigation.
    var r = _safeInvoke(_impl, arguments);
    if (r !== null) return r;

    _emitIntent(intent);
    _gotoDataSource();

    // if datasource exposes an API, call it
    try{
      if (typeof window.VSP_DATASOURCE_APPLY_DRILLDOWN_V1 === 'function'){
        return window.VSP_DATASOURCE_APPLY_DRILLDOWN_V1(intent);
      }
    }catch(_){}
    return null;
  }

  // Force window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 to be callable forever.
  function install(){
    try{
      // capture current value if any
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
      // fallback (still callable)
      _impl = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;
      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = exported;
    }
  }

  install();

  // re-assert callable (some old scripts may clobber)
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

node --check "$IMPL" >/dev/null && echo "[OK] node --check OK: $IMPL"

# (C) PATCH loader: ensure IMPL loads BEFORE dashboard scripts
echo "== patch loader to load drilldown impl first =="
LOADER="static/js/vsp_ui_loader_route_v1.js"
[ -f "$LOADER" ] || LOADER="static/js/vsp_ui_loader_route.js"
[ -f "$LOADER" ] || { echo "[ERR] cannot find loader (vsp_ui_loader_route_v1.js)"; ls -la static/js | sed -n '1,140p'; exit 3; }

cp -f "$LOADER" "$LOADER.bak_ddloader_${TS}" && echo "[BACKUP] $LOADER.bak_ddloader_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_ui_loader_route_v1.js")
if not p.exists():
    p=Path("static/js/vsp_ui_loader_route.js")
s=p.read_text(encoding="utf-8", errors="ignore")

impl="/static/js/vsp_drilldown_artifacts_impl_commercial_v1.js"
if impl in s:
    print("[OK] loader already includes impl")
else:
    # insert impl before first occurrence of vsp_dashboard_enhance_v1.js in any scripts array
    pat = r"(\[VSP_LOADER\].*?scripts\s*=\s*\[)|(\[\s*)"
    # simpler: just replace first dashboard enhance entry occurrence
    if "/static/js/vsp_dashboard_enhance_v1.js" in s:
        s = s.replace("/static/js/vsp_dashboard_enhance_v1.js", impl + ", '/static/js/vsp_dashboard_enhance_v1.js'", 1)
        # cleanup quote mismatch if needed
        s = s.replace(impl + ", '/static/js/vsp_dashboard_enhance_v1.js'", "'" + impl + "', '/static/js/vsp_dashboard_enhance_v1.js'")
        print("[OK] inserted impl before dashboard_enhance")
    else:
        # fallback: prepend near top (safe)
        s = "/* injected impl loader hint */\n" + s
        print("[WARN] did not find dashboard_enhance string; left loader unchanged")
    p.write_text(s, encoding="utf-8")
PY

node --check "$LOADER" >/dev/null && echo "[OK] node --check OK: $LOADER"

echo "[OK] commercial reset drilldown done"
