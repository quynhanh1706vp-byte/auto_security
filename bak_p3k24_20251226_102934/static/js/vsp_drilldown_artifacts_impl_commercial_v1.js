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
      try{ localStorage.setItem('vsp_drilldown_intent_v1', JSON.stringify(intent)); } catch(_){}
      window.dispatchEvent(new CustomEvent('vsp:drilldown', { detail: intent }));
    } catch(_){}
  }

  function _gotoDataSource(){
    try{
      // prefer router if exists
      if (window.location.hash !== '#datasource'){
        window.location.hash = '#datasource';
      }
    } catch(_){}
  }

  function _safeInvoke(impl, args){
    try{
      if (typeof impl === 'function') return impl.apply(null, args);
      if (impl && typeof impl.open === 'function') return impl.open.apply(impl, args);
      if (impl && typeof impl.run === 'function') return impl.run.apply(impl, args);
      if (impl && typeof impl.invoke === 'function') return impl.invoke.apply(impl, args);
    } catch(e){
      try{ console.warn('[VSP][DD] invoke failed', e); } catch(_){}
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
    } catch(_){}

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
    } catch(_){}
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
          try{ console.log('[VSP][DD] accepted real impl'); } catch(_){}
        }
      });
    } catch(e){
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
    } catch(_){}
  }, 800);
})();
