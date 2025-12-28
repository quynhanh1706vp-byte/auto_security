/*VSP_CONSOLE_FILTER_DRILLDOWN_P0_V1*/
(function(){
  try{
    if (window.__VSP_CONSOLE_FILTER_DD_P0) return;
    window.__VSP_CONSOLE_FILTER_DD_P0 = 1;

    var needle = "drilldown real impl accepted";

    function wrap(k){
      try{
        var orig = console[k];
        if (typeof orig !== "function") return;
        console[k] = function(){
          try{
            var a0 = (arguments && arguments.length) ? String(arguments[0]) : "";
            if (a0 && a0.indexOf(needle) !== -1){
              if (window.__VSP_DD_ACCEPTED_ONCE) return;
              window.__VSP_DD_ACCEPTED_ONCE = 1;
            }
          }catch(_e){}
          return orig.apply(this, arguments);
        };
      }catch(_){}
    }

    ["log","info","debug","warn"].forEach(wrap);
  }catch(_){}
})();

/* VSP_BUNDLE_COMMERCIAL_V1_PROLOGUE */
/* injected_at: 2025-12-17T16:53:25.829229 */
(function(){
  'use strict';
  try{ window.__VSP_BUNDLE_COMMERCIAL_V1 = true; }catch(_){ }
  // single entrypoint contract
  if (!window.VSP_DRILLDOWN) {
    window.VSP_DRILLDOWN = function(intent){
      try{
        if (typeof window.VSP_DRILLDOWN_IMPL === 'function') return window.VSP_DRILLDOWN_IMPL(intent);
        if (typeof window.__VSP_DD_ART_CALL__ === 'function') return window.__VSP_DD_ART_CALL__(intent);
        if (typeof window.__VSP_DRILLDOWN__ === 'function') return window.__VSP_DRILLDOWN__(intent);
        console.warn('[VSP][DRILLDOWN] no impl', intent);
        return null;
      }catch(e){ try{console.warn('[VSP][DRILLDOWN] err', e);}catch(_e){} return null; }
    };
  }
  // HARD ALIASES for legacy callers (stop TypeError)
  var alias = function(){ return window.VSP_DRILLDOWN.apply(window, arguments); };
  try{
    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== 'function') window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = alias;
    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V1 !== 'function') window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V1 = alias;
    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS !== 'function') window.VSP_DASH_DRILLDOWN_ARTIFACTS = alias;
  }catch(_){ }
})();

/* VSP_BUNDLE_COMMERCIAL_V1 */
/* built_at: 2025-12-17 16:22:48 */
/* NOTE: do NOT load vsp_ui_loader_route_v1.js in commercial mode */

(function(){
  'use strict';
  // Single public entrypoint (commercial contract)
  if (!window.VSP_DRILLDOWN) {
    window.VSP_DRILLDOWN = function(intent){
      try{
        // prefer explicit impl if provided
        if (typeof window.VSP_DRILLDOWN_IMPL === 'function') return window.VSP_DRILLDOWN_IMPL(intent);
        // common internal hooks (best-effort compat)
        if (typeof window.__VSP_DD_ART_CALL__ === 'function') return window.__VSP_DD_ART_CALL__(intent);
        if (typeof window.__VSP_DRILLDOWN__ === 'function') return window.__VSP_DRILLDOWN__(intent);
        console.warn('[VSP][DRILLDOWN] no impl', intent);
        return null;
      }catch(e){ try{console.warn('[VSP][DRILLDOWN] err', e);}catch(_){ } return null; }
    };
  }
  // Backward-compat shim (do NOT encourage direct P1_V2 usage)
  if (!window.P1_V2) window.P1_V2 = {};
  if (typeof window.P1_V2 === 'object' && !window.P1_V2.drilldown) {
    window.P1_V2.drilldown = function(intent){ return window.VSP_DRILLDOWN(intent); };
  }
})();

;
/* ==== BEGIN static/js/vsp_drilldown_stub_safe_v1.js ==== */

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


/* ==== END static/js/vsp_drilldown_stub_safe_v1.js ==== */
;
;
/* ==== BEGIN static/js/vsp_drilldown_artifacts_impl_commercial_v1.js ==== */

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


/* ==== END static/js/vsp_drilldown_artifacts_impl_commercial_v1.js ==== */
;
;
/* ==== BEGIN static/js/vsp_hash_normalize_v1.js ==== */

/* VSP_HASH_NORMALIZE_V1: normalize #tab=... or #route&k=v to #route */
(function(){
  'use strict';
  if (window.__VSP_HASH_NORMALIZE_V1) return;
  window.__VSP_HASH_NORMALIZE_V1 = 1;

  function parseHash(){
    let h = (location.hash || '').replace(/^#/, '').trim();
    if (!h) return { route: 'dashboard', params: {} };

    // split params by '&'
    const parts = h.split('&').filter(Boolean);
    let first = (parts[0] || '').trim();

    // support "#tab=datasource"
    if (first.startsWith('tab=')) first = first.slice(4).trim();
    else {
      // support "tab=" anywhere
      const m = h.match(/(?:^|&)tab=([^&]+)/);
      if (m && m[1]) first = String(m[1]).trim();
    }

    // normalize synonyms
    if (first === 'runs-reports' || first === 'reports') first = 'runs';
    if (first === 'data') first = 'datasource';
    if (first === 'rule-overrides') first = 'rules';

    const params = {};
    for (const p of parts.slice(1)){
      const i = p.indexOf('=');
      if (i > 0){
        const k = decodeURIComponent(p.slice(0,i));
        const v = decodeURIComponent(p.slice(i+1));
        params[k] = v;
      }
    }
    // also parse if first itself is like "datasource?x=y" (rare)
    if (first.includes('?')) first = first.split('?')[0];

    return { route: first || 'dashboard', params };
  }

  function normalize(){
    const { route, params } = parseHash();
    window.__VSP_HASH_ROUTE__ = route;
    window.__VSP_HASH_PARAMS__ = params;

    const target = '#' + route;
    if (location.hash !== target){
      try{
        history.replaceState(null, '', location.pathname + location.search + target);
        // trigger watchers
        window.dispatchEvent(new HashChangeEvent('hashchange'));
      }catch(_){}
    }
  }

  normalize();
  window.addEventListener('hashchange', normalize);
})();


/* ==== END static/js/vsp_hash_normalize_v1.js ==== */
;
;
/* ==== BEGIN static/js/vsp_ui_global_shims_commercial_p0_v1.js ==== */

// VSP_SAFE_DRILLDOWN_HARDEN_P0_V6
/* VSP_FORCE_ASSET_VERSION_P0_V2
 * Force cache-bust for dynamically injected /static/js/*.js scripts.
 */
(function(){
  'use strict';
  if (window.__VSP_FORCE_ASSET_VERSION_P0_V2) return;
  window.__VSP_FORCE_ASSET_VERSION_P0_V2=1;

  function ver(){
    return (window.__VSP_ASSET_V || window.VSP_ASSET_V || '20251217_142944');
  }
  function rewrite(u){
    try {
      if(!u) return u;
      if(u.indexOf('/static/js/') === -1) return u;
      // remove any existing v= param
      u = u.replace(/[?&]v=[^&]+/g, '');
      u = u.replace(/[?&]$/, '');
      var sep = (u.indexOf('?') >= 0) ? '&' : '?';
      return u + sep + 'v=' + encodeURIComponent(ver());
    } catch(_e) {
      return u;
    }
  }

  var _append = Element.prototype.appendChild;
  Element.prototype.appendChild = function(node){
    try {
      if(node && node.tagName === 'SCRIPT' && node.src) node.src = rewrite(node.src);
    } catch(_e) {}
    return _append.call(this, node);
  };

  var _setAttr = Element.prototype.setAttribute;
  Element.prototype.setAttribute = function(name, value){
    try {
      if(this && this.tagName === 'SCRIPT' && (name === 'src' || name === 'SRC') && typeof value === 'string') {
        value = rewrite(value);
      }
    } catch(_e) {}
    return _setAttr.call(this, name, value);
  };
})();

/* VSP_UI_GLOBAL_SHIMS_COMMERCIAL_P0_V1
 * 목적: UI 안정화(P0)
 *  - Fix: __VSP_DD_ART_CALL__(VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2, ...) is not a function
 *  - Fetch fallback: run_status_v2 -> run_status_v1 (+ /v1/<rid>)
 *  - Soft-degrade for missing endpoints (never throw to console)
 */
(function(){
  'use strict';
  



/* VSP_FIX_DRILLDOWN_CALLSITE_P0_V5: safe-call drilldown artifacts (function OR object.open) */
function __VSP_DD_ART_CALL__(h, ...args) {
  try {
    if (typeof h === 'function') return h(...args);
    if (h && typeof h.open === 'function') return h.open(...args);
  } catch(e) { try{console.warn('[VSP][DD_SAFE]', e);}catch(_e){} }
  return null;
}

/* VSP_FIX_DRILLDOWN_CALLSITE_P0_V3: safe-call for drilldown artifacts (function OR object.open) */
function __VSP_DD_ART_CALL__(h, ...args) {
  try {
    if (typeof h === 'function') return h(...args);
    if (h && typeof h.open === 'function') return h.open(...args);
  } catch (e) {
    try { console.warn('[VSP][DD_SAFE] call failed', e); } catch (_e) {}
  }
  return null;
}

if (window.__VSP_UI_GLOBAL_SHIMS_COMMERCIAL_P0_V1) return;
  window.__VSP_UI_GLOBAL_SHIMS_COMMERCIAL_P0_V1 = 1;

  // ---- (A) normalize drilldown artifacts callable BEFORE anyone uses it ----
  function normalizeCallable(v){
    if (typeof v === 'function') return v;
    if (v && typeof v.open === 'function') {
      const obj = v;
      const fn = function(arg){
        try { return obj.open(arg); } catch(e){ try{ console.warn('[VSP][DD] open failed', e);}catch(_){} return null; }
      };
      fn.__wrapped_from_object = true;
      return fn;
    }
    const noop = function(_arg){ return null; };
    noop.__noop = true;
    return noop;
  }

  try{
    let _val = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;
    Object.defineProperty(window, 'VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2', {
      configurable: true, enumerable: true,
      get: function(){ return _val; },
      set: function(v){ _val = normalizeCallable(v); }
    });
    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = _val;
  }catch(e){
    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = normalizeCallable(window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2);
  }

  // ---- (B) fetch fallback (targeted) ----
  const _fetch = window.fetch ? window.fetch.bind(window) : null;

  // VSP_THROTTLE_DASHBOARD_EXTRAS_P0_V2: throttle + cache + cooldown for dashboard extras to avoid spam ERR_NETWORK_CHANGED
  let __vsp_extras_cache_text = '';
  let __vsp_extras_cache_ts = 0;
  let __vsp_extras_last_try = 0;
  let __vsp_extras_last_fail = 0;
  let __vsp_extras_inflight = null;

  function __vsp_resp_json(text, status=200){
    try {
      return new Response(text || '{}', {
        status: status,
        headers: {'content-type':'application/json; charset=utf-8'}
      });
    } catch(_e) {
      // older browsers fallback
      return new Response(text || '{}');
    }
  }

  async function __vsp_fetch_extras_with_cache(url, init){
    const now = Date.now();
    const THROTTLE_MS = 10_000;   // 1 req / 10s
    const COOLDOWN_MS = 30_000;   // after fail, skip 30s
    const CACHE_OK_MS = 120_000;  // serve cache up to 2 min

    // if hidden -> prefer cache (avoid background spam)
    if (document.hidden && (now - __vsp_extras_cache_ts) < CACHE_OK_MS && __vsp_extras_cache_text) {
      return __vsp_resp_json(__vsp_extras_cache_text, 200);
    }

    // cooldown after fail
    if ((now - __vsp_extras_last_fail) < COOLDOWN_MS) {
      if (__vsp_extras_cache_text) return __vsp_resp_json(__vsp_extras_cache_text, 200);
      return __vsp_resp_json('{}', 200);
    }

    // throttle
    if ((now - __vsp_extras_last_try) < THROTTLE_MS) {
      if (__vsp_extras_cache_text) return __vsp_resp_json(__vsp_extras_cache_text, 200);
      return __vsp_resp_json('{}', 200);
    }

    __vsp_extras_last_try = now;

    // de-dup inflight
    if (__vsp_extras_inflight) {
      const t = await __vsp_extras_inflight;
      return __vsp_resp_json(t, 200);
    }

    __vsp_extras_inflight = (async () => {
      try {
        const r = await _fetch(url, init);
        const t = await r.text();
        if (r && r.ok) {
          __vsp_extras_cache_text = t || '{}';
          __vsp_extras_cache_ts = Date.now();
        }
        return (t || '{}');
      } catch(_e) {
        __vsp_extras_last_fail = Date.now();
        return (__vsp_extras_cache_text || '{}');
      } finally {
        __vsp_extras_inflight = null;
      }
    })();

    const txt = await __vsp_extras_inflight;
    return __vsp_resp_json(txt, 200);
  }
  if (_fetch) {
    function parseRidFromUrl(u){
      try{
        const url = new URL(u, window.location.origin);
        return url.searchParams.get('rid') || '';
      }catch(_){ return ''; }
    }
    function swapEndpoint(u, from, to){
      try { return u.replace(from, to); } catch(_) { return u; }
    }
    async function tryFetch(u, init){
      try { return await _fetch(u, init); } catch(_) { return null; }
    }

    window.fetch = async function(input, init){
      const url = (typeof input === 'string') ? input : (input && input.url ? input.url : '');

      // VSP_THROTTLE_DASHBOARD_EXTRAS_P0_V2: intercept dashboard extras first (avoid repeated failed XHR spam)
      if (url && url.includes('/api/vsp/dashboard_v3_extras_v1')) {
        return await __vsp_fetch_extras_with_cache(url, init);
      }
      let res = null;

      // first attempt
      res = await tryFetch(input, init);

      // if ok => return
      if (res && res.ok) return res;

      // targeted fallbacks
      if (url.includes('/api/vsp/run_status_v2')) {
        const rid = parseRidFromUrl(url);
        // 1) v2 -> v1 (same query)
        let u1 = swapEndpoint(url, '/api/vsp/run_status_v2', '/api/vsp/run_status_v1');
        let r1 = await tryFetch(u1, init);
        if (r1 && r1.ok) return r1;

        // 2) path form /run_status_v1/<rid>
        if (rid) {
          let u2 = '/api/vsp/run_status_v1/' + encodeURIComponent(rid);
          let r2 = await tryFetch(u2, init);
          if (r2 && r2.ok) return r2;
        }
        return res || r1 || null;
      }

      if (url.includes('/api/vsp/findings_effective_v1')) {
        const rid = parseRidFromUrl(url);
        // try path form /findings_effective_v1/<rid>
        if (rid) {
          let u2 = '/api/vsp/findings_effective_v1/' + encodeURIComponent(rid);
          let r2 = await tryFetch(u2, init);
          if (r2 && r2.ok) return r2;
        }
        // no hard fallback => return original (avoid throwing)
        return res;
      }

      // default: return original result (even if null)
      return res;
    };
  }
})();

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



/* ==== END static/js/vsp_ui_global_shims_commercial_p0_v1.js ==== */
;
;
/* ==== BEGIN static/js/vsp_rid_state_v1.js ==== */

/* VSP_RID_STATE_V10 (commercial stable) */
(function(){
  'use strict';

  const LOGP = '[VSP_RID_STATE_V10]';
  const LS_SELECTED = 'vsp_rid_selected_v1';
  const LS_LATEST   = 'vsp_rid_latest_v1';
  const RID_KEYS_QS = ['rid','run_id','runid'];

  function safeLSGet(k){
    try { return localStorage.getItem(k); } catch(e){ return null; }
  }
  function safeLSSet(k,v){
    try { localStorage.setItem(k, v); } catch(e){}
  }

  function qsRid(){
    try{
      const u = new URL(window.location.href);
      for(const k of RID_KEYS_QS){
        const v = u.searchParams.get(k);
        if(v && String(v).trim()) return String(v).trim();
      }
    }catch(e){}
    return null;
  }

  function getRid(){
    return qsRid() || safeLSGet(LS_SELECTED) || safeLSGet(LS_LATEST) || null;
  }

  function updateBadge(rid){
    const txt = `RID: ${rid || '(none)'}`;

    // common ids
    const ids = ['vsp-rid-badge','rid-badge','vsp_rid_badge','vspRidBadge'];
    for(const id of ids){
      const el = document.getElementById(id);
      if(el){ el.textContent = txt; return; }
    }

    // common classes / data attributes
    const el2 = document.querySelector('[data-vsp-rid-badge], .vsp-rid-badge, .rid-badge');
    if(el2){ el2.textContent = txt; return; }

    // fallback: any small element whose text starts with "RID:"
    const all = document.querySelectorAll('body *');
    for(const el of all){
      const t = (el.textContent || '').trim();
      if(t.startsWith('RID:') && t.length < 80){
        el.textContent = txt;
        return;
      }
    }
  }

  function setRid(rid, why){
    const v = (rid && String(rid).trim()) ? String(rid).trim() : null;
    if(!v) return null;
    safeLSSet(LS_SELECTED, v);
    safeLSSet(LS_LATEST, v);
    updateBadge(v);

    try{
      window.dispatchEvent(new CustomEvent('VSP_RID_CHANGED', { detail: { rid: v, why: why || 'set' } }));
    }catch(e){}
    return v;
  }

  async function pickLatestFromRunsIndex(){
    const url = '/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1';
    const r = await fetch(url, { cache: 'no-store' });
    if(!r.ok) throw new Error('runs_index not ok: ' + r.status);
    const j = await r.json();
    const it = (j && j.items && j.items[0]) ? j.items[0] : null;
    const rid = it && (it.run_id || it.rid || it.id);
    if(rid && String(rid).trim()) return String(rid).trim();
    return null;
  }

  async function pickLatest(){
    // 1) optional override: MUST return string RID or null
    try{
      const ov = window.VSP_RID_PICKLATEST_OVERRIDE_V1;
      if(typeof ov === 'function'){
        const v = await ov();
        if(typeof v === 'string' && v.trim()){
          console.log(LOGP, 'picked by override');
          return setRid(v.trim(), 'override');
        }
      }
    }catch(e){
      console.warn(LOGP, 'override failed', e);
    }

    // 2) default: runs_index
    try{
      const rid = await pickLatestFromRunsIndex();
      if(rid){
        console.log(LOGP, 'picked by runs_index', rid);
        return setRid(rid, 'runs_index');
      }
    }catch(e){
      console.warn(LOGP, 'runs_index pickLatest failed', e);
    }

    return null;
  }

  async function ensure(){
    const cur = getRid();
    updateBadge(cur);
    if(cur) return cur;
    return await pickLatest();
  }

  // compatibility exports
  window.VSP_RID_GET = getRid;
  window.VSP_RID_SET = (rid)=>setRid(rid,'manual');
  window.VSP_RID_PICKLATEST = pickLatest;

  document.addEventListener('DOMContentLoaded', ()=>{ ensure(); });
  console.log(LOGP, 'installed');
})();


/* ==== END static/js/vsp_rid_state_v1.js ==== */
;
;
/* ==== BEGIN static/js/vsp_tabs_hash_router_v1.js ==== */

(function () {
  console.log('[VSP_TABS_ROUTER_V1] clean router + header bind loaded');

  const DEFAULT_TAB = 'dashboard';

  function $(id) {
    return document.getElementById(id);
  }

  function fmtInt(n) {
    if (n == null || isNaN(n)) return '--';
    return Number(n).toLocaleString('en-US');
  }

  function fmtDate(s) {
    if (!s) return '--';
    try {
      const d = new Date(s);
      if (isNaN(d.getTime())) return String(s);
      return d.toLocaleString();
    } catch (e) {
      return String(s);
    }
  }

  // ====== PANE SETUP ======
  const PANES = {
    dashboard: 'vsp-dashboard-main',
    runs:      'vsp-runs-main',
    datasource:'vsp-datasource-main',
    settings:  'vsp-settings-main',
    rules:     'panel-rules',
  };

  function ensureExtraPanes() {
    const dash = $(PANES.dashboard);
    if (!dash) {
      console.warn('[VSP_TABS_ROUTER_V1] Không thấy #' + PANES.dashboard + ' – chỉ dùng được dashboard.');
      return;
    }
    const parent = dash.parentNode;
    const baseStyle = dash.getAttribute('style') || '';

    function ensurePane(key) {
      const id = PANES[key];
      if (!$(id)) {
        const div = document.createElement('div');
        div.id = id;
        div.setAttribute('style', baseStyle);
        div.style.display = 'none';
        parent.appendChild(div);
        console.log('[VSP_TABS_ROUTER_V1] Created pane #' + id);
      }
    }

    ensurePane('runs');
    ensurePane('datasource');
    ensurePane('settings');
    ensurePane('rules');
  }

  // ====== HEADER TABS BIND ======

  function getTabNameFromButton(btn) {
    if (!btn) return '';

    let tab =
      btn.getAttribute('data-vsp-tab') ||
      btn.getAttribute('data-tab') ||
      (btn.dataset && (btn.dataset.vspTab || btn.dataset.tab)) ||
      '';

    if (!tab) {
      const href = btn.getAttribute('href');
      if (href && href.indexOf('#') === 0) {
        tab = href.slice(1);
      }
    }

    tab = (tab || '').trim();

    // Map một số tên thường gặp về chuẩn
    if (tab === 'home') tab = 'dashboard';
    if (tab === 'runs-report' || tab === 'runs_reports') tab = 'runs';
    if (tab === 'data') tab = 'datasource';

    return tab;
  }

  function updateActiveHeader(tab) {
    const buttons = document.querySelectorAll(
      '[data-vsp-tab], [data-tab], .vsp-tab-button, .vsp-tab-btn'
    );
    buttons.forEach(function (btn) {
      const t = getTabNameFromButton(btn);
      if (!t) return;
      if (t === tab) {
        btn.classList.add('vsp-tab-active');
      } else {
        btn.classList.remove('vsp-tab-active');
      }
    });
  }

  function bindHeaderTabs() {
    const buttons = document.querySelectorAll(
      '[data-vsp-tab], [data-tab], .vsp-tab-button, .vsp-tab-btn'
    );
    if (!buttons.length) {
      console.warn('[VSP_TABS_ROUTER_V1] Không tìm thấy header tab buttons để bind.');
      return;
    }
    let bound = 0;
    buttons.forEach(function (btn) {
      const tab = getTabNameFromButton(btn);
      if (!tab) return;

      btn.addEventListener('click', function (ev) {
        // Nếu là <a href="#..."> thì chặn default để khỏi nhảy lên đầu trang
        if (ev && typeof ev.preventDefault === 'function') {
          ev.preventDefault();
        }
        console.log('[VSP_TABS_ROUTER_V1] tab click ->', tab);
        window.location.hash = '#' + tab;
      });
      bound++;
    });
    console.log('[VSP_TABS_ROUTER_V1] Bound', bound, 'header tab buttons');
  }

  // ====== RENDER HELPERS ======

  async function fetchRuns(limit) {
    const url = `/api/vsp/runs_index_v3_fs?limit=${limit || 40}`;
    const res = await fetch(url);
    if (!res.ok) throw new Error('HTTP ' + res.status);
    const data = await res.json();
    if (Array.isArray(data)) return data;
    if (Array.isArray(data.items)) return data.items;
    return [];
  }

  function renderRunsPane() {
    
    // === VSP_COMMERCIAL_RUNS_MASTER_GUARD_V1 ===
    if (window.VSP_COMMERCIAL_RUNS_MASTER) {
      console.log('[VSP_TABS_ROUTER_V1] commercial runs master enabled -> skip legacy runs hydrate');
      return;
    }
    // === END VSP_COMMERCIAL_RUNS_MASTER_GUARD_V1 ===
const pane = $(PANES.runs);
    if (!pane) return;
    pane.innerHTML = `
      <div style="padding:16px; font-size:12px; opacity:0.7;">
        Đang tải danh sách runs từ <code>/api/vsp/runs_index_v3</code>...
      </div>
    `;
    fetchRuns(40).then(items => {
      if (!items || items.length === 0) {
        pane.innerHTML = `
          <div style="padding:16px; font-size:13px; opacity:0.7;">
            Không có run nào trong lịch sử (runs_index_v3 trả về rỗng).
          </div>
        `;
        return;
      }

      const rows = items.map(item => {
        const runId   = item.run_id || item.id || '--';
        const runType = item.run_type || item.type || 'FULL_EXT';
        const created = item.started_at || item.created_at || item.created || '';
        const total   = item.total_findings != null ? item.total_findings : (item.total || 0);
        const status  = item.status || item.result || 'DONE';

        return `
          <tr style="border-bottom:1px solid rgba(148,163,184,0.2);">
            <td style="padding:8px 10px; font-size:12px; white-space:nowrap;">
              <code style="font-size:11px; opacity:0.9;">${runId}</code>
            </td>
            <td style="padding:8px 10px; font-size:12px; text-transform:uppercase; opacity:0.8;">
              ${runType}
            </td>
            <td style="padding:8px 10px; font-size:12px;">
              ${fmtDate(created)}
            </td>
            <td style="padding:8px 10px; font-size:12px; text-align:right;">
              ${fmtInt(total)}
            </td>
            <td style="padding:8px 10px; font-size:12px;">
              <span style="
                display:inline-block;
                padding:2px 8px;
                border-radius:999px;
                font-size:11px;
                text-transform:uppercase;
                letter-spacing:0.05em;
                background:rgba(34,197,94,0.12);
                border:1px solid rgba(34,197,94,0.5);
                color:#bbf7d0;
              ">
                ${status}
              </span>
            </td>
          </tr>
        `;
      }).join('');

      pane.innerHTML = `
        <div style="padding:16px 16px 8px 16px;">
          <div style="font-size:12px; text-transform:uppercase; letter-spacing:0.08em; opacity:0.7; margin-bottom:4px;">
            Runs &amp; Reports
          </div>
          <div style="font-size:12px; opacity:0.7; margin-bottom:12px;">
            Lịch sử scan mới nhất từ SECURITY_BUNDLE (runs_index_v3)
          </div>
        </div>
        <div style="padding:0 16px 16px 16px;">
          <div style="overflow:auto; border-radius:10px; border:1px solid rgba(148,163,184,0.25); background:rgba(15,23,42,0.95);">
            <table style="width:100%; border-collapse:collapse; font-family:system-ui, -apple-system, BlinkMacSystemFont, 'Inter', sans-serif; color:#e5e7eb;">
              <thead>
                <tr style="background:rgba(15,23,42,0.98);">
                  <th style="padding:8px 10px; font-size:11px; text-align:left; opacity:0.7; text-transform:uppercase;">Run ID</th>
                  <th style="padding:8px 10px; font-size:11px; text-align:left; opacity:0.7; text-transform:uppercase;">Type</th>
                  <th style="padding:8px 10px; font-size:11px; text-align:left; opacity:0.7; text-transform:uppercase;">Started</th>
                  <th style="padding:8px 10px; font-size:11px; text-align:right; opacity:0.7; text-transform:uppercase;">Total Findings</th>
                  <th style="padding:8px 10px; font-size:11px; text-align:left; opacity:0.7; text-transform:uppercase;">Status</th>
                </tr>
              </thead>
              <tbody>
                ${rows}
              </tbody>
            </table>
          </div>
        </div>
      `;
      console.log('[VSP_TABS_ROUTER_V1] Runs pane hydrated với', items.length, 'items');
    }).catch(e => {
      console.error('[VSP_TABS_ROUTER_V1] Lỗi khi load runs_index_v3', e);
      pane.innerHTML = `
        <div style="padding:16px; font-size:12px; color:#fecaca;">
          Lỗi khi tải runs_index_v3: ${e}
        </div>
      `;
    });
  }

  async function fetchDatasource(limit) {
    const url = `/api/vsp/datasource_v2?limit=${limit || 500}`;
    const res = await fetch(url);
    if (!res.ok) throw new Error('HTTP ' + res.status);
    const data = await res.json();
    if (Array.isArray(data)) return data;
    if (Array.isArray(data.items)) return data.items;
    return [];
  }

  function renderDatasourcePane() {
    const pane = $(PANES.datasource);
    if (!pane) return;
    pane.innerHTML = `
      <div style="padding:16px; font-size:12px; opacity:0.7;">
        Đang tải findings từ <code>/api/vsp/datasource_v2</code>...
      </div>
    `;
    fetchDatasource(500).then(items => {
      if (!items || items.length === 0) {
        pane.innerHTML = `
          <div style="padding:16px; font-size:13px; opacity:0.7;">
            Không có finding nào (datasource_v2 rỗng).
          </div>
        `;
        return;
      }

      const rows = items.slice(0, 300).map((f, idx) => {
        const tool  = f.tool  || f.source || '--';
        const sev   = f.severity || f.level || 'INFO';
        const rule  = f.rule_id || f.check_id || f.rule || '--';
        const file  = f.file || f.path || '--';
        const line  = f.line || f.start_line || f.end_line || '';
        return `
          <tr style="border-bottom:1px solid rgba(148,163,184,0.15);">
            <td style="padding:6px 8px; font-size:11px; opacity:0.7;">${idx + 1}</td>
            <td style="padding:6px 8px; font-size:11px;">${sev}</td>
            <td style="padding:6px 8px; font-size:11px;">${tool}</td>
            <td style="padding:6px 8px; font-size:11px;">${rule}</td>
            <td style="padding:6px 8px; font-size:11px;">${file}</td>
            <td style="padding:6px 8px; font-size:11px; text-align:right;">${line}</td>
          </tr>
        `;
      }).join('');

      pane.innerHTML = `
        <div style="padding:16px 16px 8px 16px;">
          <div style="font-size:12px; text-transform:uppercase; letter-spacing:0.08em; opacity:0.7; margin-bottom:4px;">
            Data Source
          </div>
          <div style="font-size:12px; opacity:0.7; margin-bottom:12px;">
            Bảng unified findings (tối đa 300 dòng, từ datasource_v2)
          </div>
        </div>
        <div style="padding:0 16px 16px 16px;">
          <div style="overflow:auto; border-radius:10px; border:1px solid rgba(148,163,184,0.25); background:rgba(15,23,42,0.95);">
            <table style="width:100%; border-collapse:collapse; font-family:system-ui, -apple-system, BlinkMacSystemFont, 'Inter', sans-serif; color:#e5e7eb;">
              <thead>
                <tr style="background:rgba(15,23,42,0.98);">
                  <th style="padding:6px 8px; font-size:11px; text-align:left; opacity:0.7;">#</th>
                  <th style="padding:6px 8px; font-size:11px; text-align:left; opacity:0.7;">Sev</th>
                  <th style="padding:6px 8px; font-size:11px; text-align:left; opacity:0.7;">Tool</th>
                  <th style="padding:6px 8px; font-size:11px; text-align:left; opacity:0.7;">Rule</th>
                  <th style="padding:6px 8px; font-size:11px; text-align:left; opacity:0.7;">File</th>
                  <th style="padding:6px 8px; font-size:11px; text-align:right; opacity:0.7;">Line</th>
                </tr>
              </thead>
              <tbody>
                ${rows}
              </tbody>
            </table>
          </div>
        </div>
      `;
      console.log('[VSP_TABS_ROUTER_V1] Datasource pane hydrated với', items.length, 'items');
  if (window.vspInitDatasourceTab) {
    try { window.vspInitDatasourceTab(); }
    catch (e) {
      console.error('[VSP_TABS_ROUTER_V1] vspInitDatasourceTab error:', e);
    }
  }
    }).catch(e => {
      console.error('[VSP_TABS_ROUTER_V1] Lỗi khi load datasource_v2', e);
      pane.innerHTML = `
        <div style="padding:16px; font-size:12px; color:#fecaca;">
          Lỗi khi tải datasource_v2: ${e}
        </div>
      `;
    });
  }

  async function fetchJson(url) {
    const res = await fetch(url);
    if (!res.ok) throw new Error('HTTP ' + res.status);
    return await res.json();
  }

  function renderSettingsPane() {
    const pane = $(PANES.settings);
    if (!pane) return;
    pane.innerHTML = `
      <div style="padding:16px; font-size:12px; opacity:0.7;">
        Đang tải settings từ <code>/api/vsp/settings_ui_v1</code>...
      </div>
    `;
    fetchJson('/api/vsp/settings_ui_v1').then(data => {
      const pretty = JSON.stringify(data, null, 2);
      pane.innerHTML = `
        <div style="padding:16px 16px 8px 16px;">
          <div style="font-size:12px; text-transform:uppercase; letter-spacing:0.08em; opacity:0.7; margin-bottom:4px;">
            Settings
          </div>
          <div style="font-size:12px; opacity:0.7; margin-bottom:12px;">
            Cấu hình SECURITY_BUNDLE (settings_ui_v1)
          </div>
        </div>
        <div style="padding:0 16px 16px 16px;">
          <pre style="
            margin:0;
            padding:16px;
            border-radius:10px;
            border:1px solid rgba(148,163,184,0.25);
            background:rgba(15,23,42,0.96);
            font-size:11px;
            line-height:1.4;
            overflow:auto;
            color:#e5e7eb;
          ">${pretty}</pre>
        </div>
      `;
      console.log('[VSP_TABS_ROUTER_V1] Settings pane hydrated');
    }).catch(e => {
      console.error('[VSP_TABS_ROUTER_V1] Lỗi khi load settings_ui_v1', e);
      pane.innerHTML = `
        <div style="padding:16px; font-size:12px; color:#fecaca;">
          Lỗi khi tải settings_ui_v1: ${e}
        </div>
      `;
    });
  }

  function renderRulesPane() {
    const pane = $(PANES.rules);
    if (!pane) return;
    pane.innerHTML = `
      <div style="padding:16px; font-size:12px; opacity:0.7;">
        Đang tải rule overrides từ <code>/api/vsp/rule_overrides_ui_v1</code>...
      </div>
    `;
    fetchJson('/api/vsp/rule_overrides_ui_v1').then(data => {
      const pretty = JSON.stringify(data, null, 2);
      pane.innerHTML = `
        <div style="padding:16px 16px 8px 16px;">
          <div style="font-size:12px; text-transform:uppercase; letter-spacing:0.08em; opacity:0.7; margin-bottom:4px;">
            Rule Overrides
          </div>
          <div style="font-size:12px; opacity:0.7; margin-bottom:12px;">
            Mapping / override rule (rule_overrides_ui_v1)
          </div>
        </div>
        <div style="padding:0 16px 16px 16px;">
          <pre style="
            margin:0;
            padding:16px;
            border-radius:10px;
            border:1px solid rgba(148,163,184,0.25);
            background:rgba(15,23,42,0.96);
            font-size:11px;
            line-height:1.4;
            overflow:auto;
            color:#e5e7eb;
          ">${pretty}</pre>
        </div>
      `;
      console.log('[VSP_TABS_ROUTER_V1] Rules pane hydrated');
    }).catch(e => {
      console.error('[VSP_TABS_ROUTER_V1] Lỗi khi load rule_overrides_ui_v1', e);
      pane.innerHTML = `
        <div style="padding:16px; font-size:12px; color:#fecaca;">
          Lỗi khi tải rule_overrides_ui_v1: ${e}
        </div>
      `;
    });
  }

  // ====== ROUTER ======
  const hydrated = {
    runs: false,
    datasource: false,
    settings: false,
    rules: false,
  };

  function showTab(tab) {
    tab = tab || DEFAULT_TAB;
    console.log('[VSP_TABS_ROUTER_V1] handleHashChange ->', tab);

    Object.keys(PANES).forEach(key => {
      const el = $(PANES[key]);
      if (!el) return;
      el.style.display = (key === tab) ? '' : 'none';
    });

    updateActiveHeader(tab);

    if (tab === 'runs' && !hydrated.runs) {
      hydrated.runs = true;
      renderRunsPane();
    } else if (tab === 'datasource' && !hydrated.datasource) {
      hydrated.datasource = true;
      renderDatasourcePane();
    } else if (tab === 'settings' && !hydrated.settings) {
      hydrated.settings = true;
      renderSettingsPane();
    } else if (tab === 'rules' && !hydrated.rules) {
      hydrated.rules = true;
      renderRulesPane();
    }
  }

  function handleHashChange() {
    const raw = window.location.hash || '';
    const h = raw.replace('#', '') || DEFAULT_TAB;
    showTab(h);
  }

  function init() {
    ensureExtraPanes();
    bindHeaderTabs();
    window.addEventListener('hashchange', handleHashChange);
    handleHashChange();
  }

  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    init();
  } else {
    document.addEventListener('DOMContentLoaded', init);
  }
})();

// === VSP_P2_NORMALIZE_TAB_HASH_V1 ===
(function(){
  try{
    var h = String(window.location.hash || "");
    var m = h.match(/^#tab=([a-z0-9_-]+)(.*)$/i);
    if(m){
      var tab = m[1];
      var rest = m[2] || "";
      window.location.hash = "#" + tab + rest;
    }
  }catch(e){}
})();

// ROUTE_RULES_V1: enabled 'rules' route


/* VSP_ROUTER_THROTTLE_P1_V1_BEGIN */
(function(){
  'use strict';

/* __VSP_DD_SAFE_CALL__ (P0 final): call handler as function OR {open: fn} */
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


  if (window.__VSP_ROUTER_THROTTLE_P1_V1) return;
  window.__VSP_ROUTER_THROTTLE_P1_V1 = true;

  const W = window;
  const orig = W.handleHashChange || W.__vspHandleHashChange || null;

  // If file defines handleHashChange in local scope only, fallback: patch hashchange listener to throttle.
  let last = {h:"", t:0};
  function shouldSkip(){
    const h = String(location.hash || "");
    const now = Date.now();
    if (h === last.h && (now - last.t) < 600) return true;
    last = {h, t: now};
    return false;
  }

  // If global handleHashChange exists, wrap it
  if (typeof orig === "function"){
    W.__vspHandleHashChange = orig;
    W.handleHashChange = function(){
      if (shouldSkip()) return;
      return orig.apply(this, arguments);
    };
    console.log("[VSP_ROUTER_THROTTLE_P1_V1] wrapped global handleHashChange");
    return;
  }

  // Otherwise, add throttled listener (does not remove existing; only prevents rapid duplicates)
  W.addEventListener("hashchange", function(ev){
    if (shouldSkip()) return;
  }, true);

  console.log("[VSP_ROUTER_THROTTLE_P1_V1] installed hashchange throttle (capture)");
})();
/* VSP_ROUTER_THROTTLE_P1_V1_END */



/* ==== END static/js/vsp_tabs_hash_router_v1.js ==== */
;
;
/* ==== BEGIN static/js/vsp_ui_features_v1.js ==== */

/* VSP_UI_FEATURES_V1 (route-scoped) */
(function(){
  'use strict';
  window.__VSP_FEATURE_FLAGS__ = window.__VSP_FEATURE_FLAGS__ || {
    DASHBOARD_CHARTS: true,
    RUNS_PANEL: true,
    DATASOURCE_TAB: true,
    SETTINGS_TAB: true,
    RULE_OVERRIDES_TAB: true
  };
})();


/* ==== END static/js/vsp_ui_features_v1.js ==== */
;
;
/* ==== BEGIN static/js/vsp_nav_scroll_autofix_v1.js ==== */

/* VSP_NAV_SCROLL_AUTOFIX_V1: make left nav scrollable even when CSS selector unknown */
(function(){
  function pickNavContainer(anchor){
    // Walk up and find an ancestor that contains multiple nav items (sidebar list)
    let p = anchor;
    for (let i=0; i<20 && p; i++){
      try {
        const items = p.querySelectorAll ? p.querySelectorAll(".vsp-nav-item, a.vsp-tab, a[data-tab]") : [];
        if (items && items.length >= 4) return p;
      } catch(_){}
      p = p.parentElement;
    }
    return null;
  }

  function apply(){
    const tab = document.getElementById("tab-rules");
    if (!tab) return;

    // Ensure it isn't accidentally hidden\n    tab.style.display = "";\n    tab.style.visibility = "visible";\n\n    const nav = pickNavContainer(tab) || tab.parentElement;\n    if (!nav) return;\n\n    // Make scrollable\n    nav.style.overflowY = "auto";\n    nav.style.maxHeight = "100vh";\n    nav.style.webkitOverflowScrolling = "touch";\n\n    // If nav is inside a fixed sidebar, also allow its parent to not clip\n    if (nav.parentElement){\n      nav.parentElement.style.overflow = "visible";\n    }\n    console.log("[VSP_NAV_SCROLL_AUTOFIX_V1] applied");\n  }\n\n  if (document.readyState === "loading") {\n    document.addEventListener("DOMContentLoaded", apply);\n  } else {\n    apply();\n  }\n  window.addEventListener("hashchange", apply);\n})();\n\n\n/* ==== END static/js/vsp_nav_scroll_autofix_v1.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_export_guard_v1.js ==== */\n\n/* VSP_EXPORT_GUARD_V1 */\n(function () {\n  function hidePDF() {\n    const sel = [\n      'a[href*="fmt=pdf"]',\n      'button[data-fmt="pdf"]',\n      '[data-export-fmt="pdf"]',\n      '[data-vsp-export="pdf"]'\n    ].join(",");\n\n    document.querySelectorAll(sel).forEach((n) => {\n      n.style.display = "none";\n      n.setAttribute("aria-hidden", "true");\n    });\n\n    // Heuristic: hide menu items with exact text "PDF"\n    document.querySelectorAll("a,button,li,div,span").forEach((n) => {\n      const t = (n.textContent || "").trim().toUpperCase();\n      if (t === "PDF") {\n        // hide container if it's obviously a menu item
        const box = n.closest("li") || n.closest("a") || n;
        box.style.display = "none";
      }
    });
  }

  function interceptPDFClicks() {
    document.addEventListener("click", (e) => {
      const a = e.target.closest && e.target.closest('a[href*="fmt=pdf"]');
      if (!a) return;
      e.preventDefault();
      e.stopPropagation();
      alert("PDF export is disabled in this commercial build. Use HTML or ZIP.");
    }, true);
  }

  window.addEventListener("DOMContentLoaded", () => {
    hidePDF();
    interceptPDFClicks();
    // re-hide after UI rerenders
    setTimeout(hidePDF, 800);
    setTimeout(hidePDF, 1800);
  });
})();


/* ==== END static/js/vsp_export_guard_v1.js ==== */
;
;
/* ==== BEGIN static/js/vsp_runs_verdict_badges_v1.js ==== */

/* VSP_RUNS_VERDICT_BADGES_V2 (batch + gate_policy_v3) */
(function () {

  // VSP_ROUTE_GUARD_RUNS_ONLY_V1
  function __vsp_is_runs_only_v1(){
    try {
      const h = (location.hash||"").toLowerCase();
      return h.startsWith("#runs") || h.includes("#runs/");
    } catch(_) { return false; }
  }
  if(!__vsp_is_runs_only_v1()){
    try{ console.info("[VSP_ROUTE_GUARD_RUNS_ONLY_V1] skip", "vsp_runs_verdict_badges_v1.js", "hash=", location.hash); }catch(_){}
    return;
  }

  const RID_RE = /(RUN_[A-Za-z0-9_]+_\d{8}_\d{6}|VSP_CI_\d{8}_\d{6}|VSP_[A-Z0-9]+_\d{8}_\d{6}|REQ_[A-Za-z0-9_\-]{6,})/;

  function el(tag, props = {}, children = []) {
    const e = document.createElement(tag);
    Object.assign(e, props);
    children.forEach(c => e.appendChild(typeof c === "string" ? document.createTextNode(c) : c));
    return e;
  }

  function ensureModal() {
    let m = document.getElementById("vsp-gate-modal-v1");
    if (m) return m;

    const overlay = el("div", { id: "vsp-gate-modal-v1" });
    overlay.style.position = "fixed";
    overlay.style.inset = "0";
    overlay.style.zIndex = "99999";
    overlay.style.background = "rgba(0,0,0,0.55)";
    overlay.style.display = "none";
    overlay.addEventListener("click", (e) => { if (e.target === overlay) overlay.style.display = "none"; });

    const card = el("div");
    card.style.position = "absolute";
    card.style.top = "10%";
    card.style.left = "50%";
    card.style.transform = "translateX(-50%)";
    card.style.width = "min(900px, 92vw)";
    card.style.maxHeight = "80vh";
    card.style.overflow = "auto";
    card.style.borderRadius = "16px";
    card.style.border = "1px solid rgba(255,255,255,0.16)";
    card.style.background = "rgba(2,6,23,0.96)";
    card.style.padding = "14px 14px";
    card.style.color = "rgba(255,255,255,0.92)";
    card.style.boxShadow = "0 18px 60px rgba(0,0,0,0.45)";

    const header = el("div");
    header.style.display = "flex";
    header.style.alignItems = "center";
    header.style.justifyContent = "space-between";
    header.style.gap = "10px";

    const title = el("div", { id: "vsp-gate-modal-title-v1" });
    title.style.fontWeight = "800";
    title.style.fontSize = "14px";

    const close = el("button", { innerText: "Close" });
    close.style.cursor = "pointer";
    close.style.padding = "6px 10px";
    close.style.borderRadius = "999px";
    close.style.border = "1px solid rgba(255,255,255,0.16)";
    close.style.background = "rgba(15,23,42,0.6)";
    close.style.color = "rgba(255,255,255,0.92)";
    close.addEventListener("click", () => overlay.style.display = "none");

    header.appendChild(title);
    header.appendChild(close);

    const body = el("div", { id: "vsp-gate-modal-body-v1" });
    body.style.marginTop = "10px";
    body.style.fontSize = "12px";
    body.style.lineHeight = "1.5";
    body.style.whiteSpace = "pre-wrap";

    card.appendChild(header);
    card.appendChild(body);
    overlay.appendChild(card);
    document.body.appendChild(overlay);
    return overlay;
  }

  function badgeStyle(verdict) {
    const v = (verdict || "UNKNOWN").toUpperCase();
    const base = {
      display: "inline-flex",
      alignItems: "center",
      gap: "8px",
      fontSize: "11px",
      fontWeight: "800",
      padding: "4px 10px",
      borderRadius: "999px",
      border: "1px solid rgba(255,255,255,0.16)",
      background: "rgba(15,23,42,0.65)",
      cursor: "pointer",
      userSelect: "none",
      whiteSpace: "nowrap",
    };
    if (v.includes("RED") || v.includes("FAIL")) base.boxShadow = "0 0 0 1px rgba(239,68,68,0.25) inset";
    else if (v.includes("AMBER") || v.includes("WARN")) base.boxShadow = "0 0 0 1px rgba(245,158,11,0.25) inset";
    else if (v.includes("GREEN") || v.includes("PASS")) base.boxShadow = "0 0 0 1px rgba(34,197,94,0.25) inset";
    else base.boxShadow = "0 0 0 1px rgba(148,163,184,0.25) inset";
    return base;
  }

  function attachBadge(target, rid, gp) {
    if (!target || !rid || !gp) return;
    if (target.querySelector?.(`[data-vsp-gate-badge="1"][data-rid="${rid}"]`)) return;

    const verdict = (gp.verdict || "UNKNOWN").toUpperCase();
    const degN = Number(gp.degraded_n || 0);

    const b = el("span");
    b.dataset.vspGateBadge = "1";
    b.dataset.rid = rid;
    b.innerText = `VERDICT: ${verdict}${degN ? ` · DEG:${degN}` : ""}`;
    Object.assign(b.style, badgeStyle(verdict));

    b.addEventListener("click", () => {
      const overlay = ensureModal();
      const title = document.getElementById("vsp-gate-modal-title-v1");
      const body = document.getElementById("vsp-gate-modal-body-v1");
      title.textContent = `Run: ${rid} · Verdict: ${verdict}${degN ? ` · DEG:${degN}` : ""}`;

      const reasons = Array.isArray(gp.reasons) ? gp.reasons : (gp.reasons ? [String(gp.reasons)] : []);
      const degItems = Array.isArray(gp.degraded_items) ? gp.degraded_items : [];

      const lines = [];
      lines.push(`Source: ${gp.source || "unknown"}`);
      lines.push("");
      lines.push("Reasons:");
      if (reasons.length) reasons.forEach((x) => lines.push(`- ${x}`));
      else lines.push("- (none)");
      lines.push("");
      lines.push("Degraded:");
      if (degItems.length) degItems.forEach((x) => lines.push(`- ${x}`));
      else lines.push("- (none)");

      body.textContent = lines.join("\n");
      overlay.style.display = "block";
    });

    target.appendChild(document.createTextNode(" "));
    target.appendChild(b);
  }

  function extractRidFromNode(node) {
    const txt = (node?.innerText || node?.textContent || "").trim();
    const m1 = txt.match(RID_RE);
    if (m1) return m1[1];
    const a = node?.querySelector?.("a[href]") || null;
    if (a) {
      const m2 = a.getAttribute("href").match(RID_RE);
      if (m2) return m2[1];
    }
    return null;
  }

  async function loadRunsIndexMap() {
    try {
      const r = await fetch("/api/vsp/runs_index_v3_fs_resolved?limit=80&hide_empty=0&filter=1");
      if (!r.ok) return new Map();
      const j = await r.json();
      const items = j?.items || [];
      const m = new Map();
      items.forEach((it) => {
        const rid = it.run_id || it.id || it.rid;
        const ci = it.ci_run_dir || it.ci || it.run_dir;
        if (rid && ci) m.set(String(rid), String(ci));
      });
      return m;
    } catch {
      return new Map();
    }
  }

  async function fetchBatch(ridToCi) {
    const items = Array.from(ridToCi.entries()).map(([rid, ci_run_dir]) => ({ rid, ci_run_dir }));
    const r = await fetch("/api/vsp/gate_policy_batch_v1", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ items })
    });
    if (!r.ok) return [];
    const j = await r.json();
    return j?.items || [];
  }

  async function patchDashboardHeader() {
    const anchor =
      document.querySelector(".vsp-page-title") ||
      document.querySelector("h1") ||
      document.querySelector(".dashboard-title") ||
      null;
    if (!anchor) return;

    try {
      const dRes = await fetch("/api/vsp/dashboard_v3");
      if (!dRes.ok) return;
      const d = await dRes.json();
      const rid = d?.run_id || d?.latest_run_id || d?.current_run_id;
      if (!rid) return;

      // resolve ci_run_dir via run_status_v2 (cheap, 1 call)
      const sRes = await fetch(`/api/vsp/run_status_v2/${encodeURIComponent(rid)}`);
      const st = sRes.ok ? await sRes.json() : {};
      const ci = st?.ci_run_dir || null;

      const u = `/api/vsp/gate_policy_v3/${encodeURIComponent(rid)}${ci ? `?ci_run_dir=${encodeURIComponent(ci)}` : ""}`;
      const gRes = await fetch(u);
      if (!gRes.ok) return;
      const gp = await gRes.json();
      if (!gp || gp.ok === false) return;

      attachBadge(anchor.parentElement || anchor, rid, gp);
    } catch {}
  }

  async function patchRunsTable() {
    const roots = Array.from(document.querySelectorAll("table, .vsp-table, .runs-table, .vsp-runs, #tab-runs, [data-tab='runs']"));
    const scope = roots.length ? roots : [document.body];

    const ridToTargets = new Map();
    scope.forEach((root) => {
      const rows = root.querySelectorAll("tr, .row, .vsp-row, li, .vsp-run-item");
      rows.forEach((row) => {
        const rid = extractRidFromNode(row);
        if (!rid) return;
        if (!ridToTargets.has(rid)) ridToTargets.set(rid, []);
        ridToTargets.get(rid).push(row);
      });
    });

    const rids = Array.from(ridToTargets.keys()).slice(0, 50);
    if (!rids.length) return;

    const idx = await loadRunsIndexMap();
    const ridToCi = new Map();
    rids.forEach((rid) => {
      const ci = idx.get(rid) || idx.get(rid.replace(/^RUN_/, "")) || null;
      ridToCi.set(rid, ci);
    });

    const items = await fetchBatch(ridToCi);
    const byRid = new Map();
    items.forEach((it) => byRid.set(it.run_id, it));

    rids.forEach((rid) => {
      const gp = byRid.get(rid) || null;
      if (!gp) return;
      (ridToTargets.get(rid) || []).forEach((row) => {
        const place = row.querySelector("td") || row.querySelector(".title") || row.querySelector("a") || row;
        attachBadge(place, rid, gp);
      });
    });
  }

  window.addEventListener("DOMContentLoaded", () => {
    patchDashboardHeader();
    setTimeout(patchRunsTable, 600);
    setTimeout(patchRunsTable, 1600);
  });
})();


/* ==== END static/js/vsp_runs_verdict_badges_v1.js ==== */
;
;
/* ==== BEGIN static/js/vsp_runs_tab_resolved_v1.js ==== */

// VSP_SAFE_DRILLDOWN_HARDEN_P0_V6
/* VSP_RUNS_TAB_RESOLVED_V3 (P1 commercial): use runs_index flags only (NO per-row status fetch) */

/* __VSP_DD_HANDLER_WRAP_P0_FINAL: normalize VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 to callable */
(function(){
  'use strict';

/* VSP_DD_ART_CALL_V1: commercial stable wrapper (fn OR {open:fn}) */
(function(){
  'use strict';
  if (window.VSP_DD_ART_CALL_V1) return;
  window.VSP_DD_ART_CALL_V1 = function(){
    var h = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;
    var args = Array.prototype.slice.call(arguments);
    try{
      if (typeof h === 'function') return h.apply(null, args);
      if (h && typeof h.open === 'function') return h.open.apply(h, args);
    }catch(e){
      try{ console.warn('[VSP][DD_CALL_V1]', e); }catch(_){}
    }
    return null;
  };
})();


  try{
    var h = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;
    if (h && typeof h !== 'function'){
      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){
        return (window.__VSP_DD_SAFE_CALL__ || function(x){
          try{
            var a=[].slice.call(arguments,1);
            if (typeof x==='function') return x.apply(null,a);
            if (x && typeof x.open==='function') return x.open.apply(x,a);
          }catch(_){}
          return null;
        }).apply(null, [h].concat([].slice.call(arguments)));
      };
      try{ console.log('[VSP][P0] drilldown handler wrapped (obj->fn)'); }catch(_){}
    }
  }catch(e){}
})();

(function(){
  'use strict';

  // VSP_ROUTE_GUARD_RUNS_ONLY_V1
  function __vsp_is_runs_only_v1(){
    try {
      const h = (location.hash||"").toLowerCase();
      return h.startsWith("#runs") || h.includes("#runs/");
    } catch(_) { return false; }
  }
  if(!__vsp_is_runs_only_v1()){
    try{ console.info("[VSP_ROUTE_GUARD_RUNS_ONLY_V1] skip", "vsp_runs_tab_resolved_v1.js", "hash=", location.hash); }catch(_){}
    return;
  }


  if (window.__VSP_RUNS_V3_INITED) return;
  window.__VSP_RUNS_V3_INITED = true;

  const API_RUNS = "/api/vsp/runs_index_v3_fs_resolved";
  const API_STATUS = "/api/vsp/run_status_v2"; // link only
  const EXPORT_BASE = "/api/vsp/run_export_v3";
  const ART_BASE = "/api/vsp/artifacts_index_v1";

  function $(sel, root){ return (root||document).querySelector(sel); }
  function $all(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }
  function esc(s){ return String(s ?? "").replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }\n  function visibleEl(el){\n    if (!el) return false;\n    const r = el.getBoundingClientRect();\n    return !!(el.offsetParent !== null && r.width > 240 && r.height > 160);\n  }\n  function pickBestContainer(){\n    const cands = [\n      "#tab-runs","#vsp4-runs","[data-tab='runs']","#runs",\n      "#tabpane-runs","#pane-runs","#panel-runs",\n      ".tab-pane.active",".tab-pane.is-active",\n      ".vsp-main",".vsp-content","main",".content","#content",".page-content",\n      "body"\n    ];\n    let best = document.body, bestArea = 0;\n    for (const sel of cands){\n      for (const el of $all(sel)){\n        if (!visibleEl(el)) continue;\n        const r = el.getBoundingClientRect();\n        const area = r.width * r.height;\n        if (area > bestArea){\n          bestArea = area;\n          best = el;\n        }\n      }\n    }\n    return best || document.body;\n  }\n\n  function boolAttr(v){\n    if (v === true) return "1";\n    if (v === false) return "0";\n    return "?";\n  }\n\n  function normalizeItems(json){\n    const items = (json && (json.items || json.data || json.runs)) || [];\n    return Array.isArray(items) ? items : [];\n  }\n\n  function ensureUI(root){\n    let tb = $("#vsp-runs-toolbar", root);\n    if (!tb){\n      tb = document.createElement("div");\n      tb.id = "vsp-runs-toolbar";\n      tb.className = "vsp-card vsp-card--tight";\n      tb.style.marginBottom = "10px";\n      tb.innerHTML = `\n        <div style="display:flex; gap:10px; flex-wrap:wrap; align-items:center;">\n          <div style="display:flex; gap:8px; align-items:center;">\n            <label style="opacity:.9">Limit</label>\n            <select id="vsp-runs-limit" class="vsp-input">\n              <option value="10">10</option>\n              <option value="20">20</option>\n              <option value="50" selected>50</option>\n              <option value="100">100</option>\n              <option value="200">200</option>\n            </select>\n          </div>\n\n          <div style="display:flex; gap:8px; align-items:center;">\n            <label style="opacity:.9">Has findings</label>\n            <select id="vsp-runs-filter-hf" class="vsp-input">\n              <option value="all" selected>All</option>\n              <option value="1">Yes</option>\n              <option value="0">No</option>\n              <option value="?">Unknown</option>\n            </select>\n          </div>\n\n          <div style="display:flex; gap:8px; align-items:center;">\n            <label style="opacity:.9">Degraded</label>\n            <select id="vsp-runs-filter-deg" class="vsp-input">\n              <option value="all" selected>All</option>\n              <option value="1">Yes</option>\n              <option value="0">No</option>\n              <option value="?">Unknown</option>\n            </select>\n          </div>\n\n          <div style="display:flex; gap:8px; align-items:center; flex:1; min-width:240px;">\n            <label style="opacity:.9">Search</label>\n            <input id="vsp-runs-search" class="vsp-input" placeholder="run_id / target / status..." style="flex:1; min-width:180px;" />\n          </div>\n\n          <button id="vsp-runs-refresh" class="vsp-btn">Refresh</button>\n          <span id="vsp-runs-meta" style="opacity:.8"></span>\n        </div>\n      `;\n      root.prepend(tb);\n    }\n\n    let table = $("#vsp-runs-table", root);\n    if (!table){\n      table = document.createElement("table");\n      table.id = "vsp-runs-table";\n      table.className = "vsp-table";\n      table.style.width = "100%";\n      table.innerHTML = `\n        <thead>\n          <tr>\n            <th style="width:200px;">Time</th>\n            <th>Run ID</th>\n            <th style="width:140px;">Target</th>\n            <th style="width:120px;">Status</th>\n            <th style="width:140px;">Findings</th>\n            <th style="width:140px;">Degraded</th>\n            <th style="width:220px;">Actions</th>\n          </tr>\n        </thead>\n        <tbody id="vsp-runs-tbody"></tbody>\n      `;\n      root.insertBefore(table, tb.nextSibling);\n    }\n\n    const tbody = $("#vsp-runs-tbody", root) || table.querySelector("tbody");\n    return {tb, table, tbody};\n  }\n\n  function renderRow(item){\n    const rid = String(item.run_id || item.rid || item.id || "");\n    const created = item.ts || item.created_at || item.created || item.time || item.started_at || "";\n    const target = item.target_id || item.target || item.profile || item.app || "";\n    const status = item.status || item.stage || item.state || "";\n\n    const total = (typeof item.total_findings === "number") ? item.total_findings : null;\n    const hasF = (typeof item.has_findings === "boolean") ? item.has_findings : (total !== null ? total > 0 : null);\n    const dn = (typeof item.degraded_n === "number") ? item.degraded_n : null;\n    const da = (typeof item.degraded_any === "boolean") ? item.degraded_any : (dn !== null ? dn > 0 : null);\n\n    const hfAttr = boolAttr(hasF);\n    const dgAttr = boolAttr(da);\n\n    const hfText =\n      hfAttr === "1" ? `YES${(typeof total === "number") ? ` (${total})` : ""}` :\n      hfAttr === "0" ? `NO${(typeof total === "number") ? " (0)" : ""}` :\n      "UNKNOWN";\n\n    const dgText =\n      dgAttr === "1" ? `YES${(typeof dn === "number") ? ` (${dn})` : ""}` :\n      dgAttr === "0" ? `NO${(typeof dn === "number") ? " (0)" : ""}` :\n      "UNKNOWN";\n\n    const tr = document.createElement("tr");\n    tr.dataset.rid = rid;\n    tr.setAttribute("data-has-findings", hfAttr);\n    tr.setAttribute("data-degraded", dgAttr);\n\n    tr.innerHTML = `\n      <td>${esc(created)}</td>\n      <td><code>${esc(rid)}</code></td>\n      <td>${esc(target)}</td>\n      <td>${esc(status)}</td>\n      <td><span class="vsp-pill" data-role="hf">${esc(hfText)}</span></td>\n      <td><span class="vsp-pill" data-role="deg">${esc(dgText)}</span></td>\n      <td style="display:flex; gap:8px; flex-wrap:wrap;">\n        <a class="vsp-btn vsp-btn--ghost" href="${esc(API_STATUS + "/" + encodeURIComponent(rid))}" target="_blank" rel="noopener">status</a>\n        <a class="vsp-btn vsp-btn--ghost" href="${esc(ART_BASE + "/" + encodeURIComponent(rid))}" target="_blank" rel="noopener">artifacts</a>\n        <a class="vsp-btn vsp-btn--ghost" href="${esc("/api/vsp/run_export_cio_v2/" + encodeURIComponent(rid) + "?fmt=html")}" target="_blank" rel="noopener">cio</a>\n<a class="vsp-btn vsp-btn--ghost" href="${esc(EXPORT_BASE + "/" + encodeURIComponent(rid) + "?fmt=html")}" target="_blank" rel="noopener">html</a>\n        <a class="vsp-btn vsp-btn--ghost" href="${esc(EXPORT_BASE + "/" + encodeURIComponent(rid) + "?fmt=zip")}" target="_blank" rel="noopener">zip</a>\n        <a class="vsp-btn vsp-btn--ghost" href="${esc(EXPORT_BASE + "/" + encodeURIComponent(rid) + "?fmt=pdf")}" target="_blank" rel="noopener">pdf</a>\n      </td>\n    `;\n    return tr;\n  }\n\n  function applyFilters(root){\n    const hf = $("#vsp-runs-filter-hf", root)?.value || "all";\n    const dg = $("#vsp-runs-filter-deg", root)?.value || "all";\n    const q  = ($("#vsp-runs-search", root)?.value || "").trim().toLowerCase();\n\n    const rows = $all("#vsp-runs-tbody tr", root);\n    let shown = 0;\n\n    for (const tr of rows){\n      const rhf = tr.getAttribute("data-has-findings") || "?";\n      const rdg = tr.getAttribute("data-degraded") || "?";\n\n      let ok = true;\n      if (hf !== "all" && rhf !== hf) ok = false;\n      if (dg !== "all" && rdg !== dg) ok = false;\n\n      if (ok && q){\n        const hay = (tr.textContent || "").toLowerCase();\n        if (!hay.includes(q)) ok = false;\n      }\n\n      tr.hidden = !ok;\n      if (ok) shown++;\n    }\n\n    const meta = $("#vsp-runs-meta", root);\n    if (meta) meta.textContent = `Showing ${shown}/${rows.length}`;\n  }\n\n  async function loadRuns(root){\n    const limit = parseInt($("#vsp-runs-limit", root)?.value || "50", 10) || 50;\n    const url = `${API_RUNS}?limit=${encodeURIComponent(String(limit))}&hide_empty=0&filter=1`;\n\n    const meta = $("#vsp-runs-meta", root);\n    if (meta) meta.textContent = "Loading runs...";\n\n    const r = await fetch(url, {credentials:"same-origin"});\n    const json = await r.json().catch(() => ({}));\n    const items = normalizeItems(json);\n\n    window.__vspRunsItems = items;\n\n    const {tbody} = ensureUI(root);\n    tbody.innerHTML = "";\n    for (const it of items){\n      tbody.appendChild(renderRow(it));\n    }\n\n    applyFilters(root);\n    if (meta) meta.textContent = `Loaded ${items.length} (flags from runs_index).`;\n  }\n\n  function bind(root){\n    $("#vsp-runs-refresh", root)?.addEventListener("click", () => loadRuns(root).catch(e => console.error("[VSP_RUNS] load error", e)));\n    $("#vsp-runs-limit", root)?.addEventListener("change", () => loadRuns(root).catch(e => console.error("[VSP_RUNS] load error", e)));\n\n    const onFilter = () => applyFilters(root);\n    $("#vsp-runs-filter-hf", root)?.addEventListener("change", onFilter);\n    $("#vsp-runs-filter-deg", root)?.addEventListener("change", onFilter);\n    $("#vsp-runs-search", root)?.addEventListener("input", onFilter);\n  }\n\n  function init(){\n    const root = pickBestContainer();\n    ensureUI(root);\n    bind(root);\n    loadRuns(root).catch(e => console.error("[VSP_RUNS] init load error", e));\n  }\n\n  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);\n  else init();\n})();\n\n\n/* ==== END static/js/vsp_runs_tab_resolved_v1.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_datasource_tab_v1.js ==== */\n\n/* VSP_DATASOURCE_TAB_V1 (commercial P1): RID -> findings_unified API + filters + paging */\n(function(){\n  'use strict';\n\n  function normalizeRid(x){\n    x = String(x||"").trim();\n    // common: RUN_<RID>\n    x = x.replace(/^RUN[_\s]+/i, "");\n    // try extract canonical VSP_CI_YYYYmmdd_HHMMSS\n    const m = x.match(/(VSP_CI_\d{8}_\d{6})/i);\n    if (m) return m[1];\n    // fallback: collapse spaces -> underscores\n    x = x.replace(/\s+/g, "_");\n    return x;\n  }\n\n\n\n  const $ = (sel, root=document) => root.querySelector(sel);\n\n  async function getActiveRid(){\n    // Prefer rid state injected by vsp_rid_state_v1.js (your template already loads it)\n    try{\n      if (window.VSP_RID_STATE && typeof window.VSP_RID_STATE.get === "function"){\n        const r = window.VSP_RID_STATE.get();\n        if (r) return r;\n      }\n    }catch(_){}\n\n    // Fallback: dashboard_v3 run_id (best-effort)\n    try{\n      const j = await fetch("/api/vsp/dashboard_v3").then(r=>r.json());\n      if (j && j.run_id) return j.run_id;\n    }catch(_){}\n\n    return null;\n  }\n\n  function esc(s){\n    return String(s ?? "").replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));\n  }\n\n  function renderTable(items){\n    const host = $("#vsp4-datasource-table") || $("#datasource-table") || $("#tab-datasource");\n    if (!host) return;\n\n    const rows = (items||[]).map(it=>{\n      const sev = esc(it.severity||"");\n      const tool = esc(it.tool||"");\n      const title = esc(it.title||"");\n      const file = esc(it.file||"");\n      const line = esc(it.line||"");\n      const cwe = Array.isArray(it.cwe) ? esc(it.cwe[0]||"") : esc(it.cwe||"");\n      return `<tr>\n        <td class="vsp-mono">${sev}</td>\n        <td class="vsp-mono">${tool}</td>\n        <td>${title}</td>\n        <td class="vsp-mono">${cwe}</td>\n        <td class="vsp-mono">${file}:${line}</td>\n      </tr>`;\n    }).join("");\n\n    host.innerHTML = `\n      <div class="vsp-row" style="gap:10px; align-items:center; margin:10px 0;">\n        <input id="ds-q" class="vsp-input" style="min-width:260px" placeholder="search title/file/id..." />\n        <input id="ds-file" class="vsp-input" style="min-width:220px" placeholder="file contains..." />\n        <select id="ds-sev" class="vsp-input">\n          <option value="">SEV (all)</option>\n          <option>CRITICAL</option><option>HIGH</option><option>MEDIUM</option>\n          <option>LOW</option><option>INFO</option><option>TRACE</option>\n        </select>\n        <select id="ds-tool" class="vsp-input" style="min-width:180px"><option value="">TOOL (all)</option></select>\n        <input id="ds-cwe" class="vsp-input" style="min-width:140px" placeholder="CWE-79" />\n        <button id="ds-go" class="vsp-btn">Apply</button>\n        <span id="ds-meta" class="vsp-muted" style="margin-left:auto;"></span>\n      </div>\n      <div class="vsp-row" style="gap:10px; align-items:center; margin:10px 0;">\n        <button id="ds-prev" class="vsp-btn vsp-btn-ghost">Prev</button>\n        <button id="ds-next" class="vsp-btn vsp-btn-ghost">Next</button>\n        <input id="ds-limit" class="vsp-input" style="width:90px" value="50" />\n        <span class="vsp-muted">limit (1..500)</span>\n      </div>\n      <div class="vsp-card" style="overflow:auto;">\n        <table class="vsp-table" style="min-width:1100px">\n          <thead><tr>\n            <th>Severity</th><th>Tool</th><th>Title</th><th>CWE</th><th>File:Line</th>\n          </tr></thead>\n          <tbody>${rows || `<tr><td colspan="5" class="vsp-muted">No items</td></tr>`}</tbody>\n        </table>\n      </div>\n    `;\n  }\n\n  function populateToolOptions(byTool){\n    const sel = document.querySelector('#ds-tool');\n    if(!sel) return;\n    const cur = sel.value || '';\n    const keys = Object.keys(byTool||{}).sort((a,b)=>String(a).localeCompare(String(b)));\n    sel.innerHTML = '<option value="">TOOL (all)</option>' + keys.map(k=>`<option value="${k}">${k} (${byTool[k]})</option>`).join('');\n    if(cur) sel.value = cur;\n  }\n\n  async function load(page){\n    const rid = normalizeRid(normalizeRid(await getActiveRid()));\n    const meta = $("#ds-meta");\n    if (!rid){\n      renderTable([]);\n      if (meta) meta.textContent = "RID: (missing)";\n      return;\n    }\n\n    const q = ($("#ds-q")?.value || "").trim();\n    const fileq = ($("#ds-file")?.value || "").trim();\n    const sev = ($("#ds-sev")?.value || "").trim();\n    const tool = ($("#ds-tool")?.value || "").trim();\n    const cwe = ($("#ds-cwe")?.value || "").trim();\n    const limit = parseInt(($("#ds-limit")?.value || "50"), 10) || 50;\n\n    const params = new URLSearchParams();\n    params.set("page", String(page||1));\n    params.set("limit", String(limit));\n    if (q) params.set("q", q);\n    if (fileq) params.set("file", fileq);\n    if (sev) params.set("sev", sev);\n    if (tool) params.set("tool", tool);\n    if (cwe) params.set("cwe", cwe);\n\n    const url = `/api/vsp/findings_unified_v2/${encodeURIComponent(rid)}?` + params.toString();\n    const j = await fetch(url).then(r=>r.json()).catch(()=>null);\n\n    if (!j){\n      renderTable([]);\n      if (meta) meta.textContent = `RID=${rid} | fetch failed`;\n      return;\n    }\n\n    if (j.warning && j.warning.includes("run_dir_not_found")){\n      renderTable([]);\n      if (meta) meta.textContent = `RID=${rid} | run_dir_not_found (RID state not persisted?)`;\n      return;\n    }\n\n    renderTable(j.items || []);\n    try{ populateToolOptions((j.counts||{}).by_tool||{}); }catch(_){ }\n\n    const total = j.total ?? 0;\n    const p = j.page ?? 1;\n    const l = j.limit ?? limit;\n    const start = total ? ((p-1)*l + 1) : 0;\n    const end = Math.min(total, (p*l));\n    const src = j.resolve_source || "-";\n    const warn = j.warning ? ` | ${j.warning}` : "";\n    const sevCounts = (j.counts||{}).by_sev||{};\nconst sevMini = Object.keys(sevCounts).sort().map(k=>`${k}:${sevCounts[k]}`).join(" ");\nif ($("#ds-meta")) $("#ds-meta").textContent = `RID=${rid} | ${start}-${end}/${total} | ${sevMini} | src=${src}${warn}`;\n\n    // wire buttons\n    $("#ds-go")?.addEventListener("click", ()=>load(1));\n    $("#ds-prev")?.addEventListener("click", ()=>load(Math.max(1, (p-1))));\n    $("#ds-next")?.addEventListener("click", ()=>load((p+1)));\n  }\n\n  // expose for debugging\n  window.VSP_DS_P1 = { reload: ()=>load(1) };\n\n  // auto-load when tab exists\n  document.addEventListener("DOMContentLoaded", ()=> {\n    // First render shell then load data\n    renderTable([]);\n    load(1);\n  });\n})();\n\n\n/* ==== END static/js/vsp_datasource_tab_v1.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_rule_overrides_tab_v1.js ==== */\n\n/* VSP_RULE_OVERRIDES_GUARD_V2_BEGIN */\n(function(){\n  'use strict';\n  if (typeof window === 'undefined') return;\n\n  window.__vspGetRidSafe = async function(){\n    try{\n      if (typeof window.VSP_RID_PICKLATEST_OVERRIDE_V1 === 'function'){\n        const rid = await window.VSP_RID_PICKLATEST_OVERRIDE_V1();\n        if (rid) return rid;\n      }\n    }catch(_e){}\n    try{\n      if (window.VSP_RID_STATE && typeof window.VSP_RID_STATE.pickLatest === 'function'){\n        const rid = await window.VSP_RID_STATE.pickLatest();\n        if (rid) return rid;\n      }\n    }catch(_e){}\n    return null;\n  };\n})();\n /* VSP_RULE_OVERRIDES_GUARD_V2_END */\n\n/* VSP_RULEOVERRIDES_GUARD_V1_BEGIN */\n// commercial safety: don't crash if rid override hook not present
try {
  if (!window.VSP_RID_PICKLATEST_OVERRIDE_V1) {
    window.VSP_RID_PICKLATEST_OVERRIDE_V1 = function(items) {
      return (items && items[0]) ? items[0] : null;
    };
  }
} catch(e) {}
/* VSP_RULEOVERRIDES_GUARD_V1_END */
/* VSP_RULE_OVERRIDES_TAB_V1: clean + CRUD (GET/POST) */
(function(){

const API = "/api/vsp/rule_overrides_v1";
  const $ = (id)=>document.getElementById(id);

  function esc(s){
    return String(s==null?'':s)
      .replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;")
      .replace(/"/g,"&quot;").replace(/'/g,"&#39;");\n  }\n  function nowIsoDate(){\n    const d=new Date(); const y=d.getFullYear();\n    const m=String(d.getMonth()+1).padStart(2,'0');\n    const day=String(d.getDate()).padStart(2,'0');\n    return `${y}-${m}-${day}`;\n  }\n  function msg(t, kind){\n    const el=$("rules-msg");\n    if(!el) return;\n    el.textContent = t || "";\n    el.style.opacity = t ? "1" : "0.85";\n    el.style.color = kind==="err" ? "rgba(248,113,113,0.95)" : "rgba(148,163,184,0.95)";\n  }\n\n  function normalizeFromApi(obj){\n    // Accept: {version,items:[...]} OR {meta,overrides:[...]}\n    if(!obj || typeof obj!=='object') return {version:1, items:[]};\n    if(Array.isArray(obj.items)) return {version: obj.version||1, items: obj.items||[]};\n    if(Array.isArray(obj.overrides)) return {version: 1, items: obj.overrides||[]};\n    if(obj.meta && Array.isArray(obj.meta.overrides)) return {version: 1, items: obj.meta.overrides||[]};\n    return {version: 1, items: []};\n  }\n\n  function toPostPayload(state){\n    // Prefer commercial schema you already used:\n    // {meta:{version:"v1"}, overrides:[{match:{...}, set:{...}, action, justification, expires_at, id}]}\n    return { meta:{version:"v1"}, overrides: (state.items||[]).map(x=>x||{}) };\n  }\n\n  async function apiGet(){\n    const r = await fetch(API, { cache:"no-store", credentials:"same-origin" });\n    if(!r.ok) throw new Error("GET failed: "+r.status);\n    return await r.json();\n  }\n  async function apiSave(payload){\n    const r = await fetch(API, {\n      method:"POST",\n      headers:{ "Content-Type":"application/json" },\n      body: JSON.stringify(payload),\n      credentials:"same-origin",\n    });\n    if(!r.ok){\n      const t = await r.text().catch(()=> "");\n      throw new Error("POST failed: "+r.status+" "+t.slice(0,200));\n    }\n    return await r.json();\n  }\n\n  function render(container, state){\n    const items = Array.isArray(state.items) ? state.items : [];\n    const html = `\n      <div class="vsp-card" style="margin:12px 0; padding:14px;">\n        <div style="display:flex; gap:10px; align-items:center; justify-content:space-between; flex-wrap:wrap;">\n          <div>\n            <div style="font-weight:800; font-size:16px;">Rule Overrides</div>\n            <div style="opacity:.75; font-size:12px;">API: <code>${esc(API)}</code></div>\n          </div>\n          <div style="display:flex; gap:8px; align-items:center;">\n            <button class="vsp-btn vsp-btn-soft" id="rules-reload">Reload</button>\n            <button class="vsp-btn vsp-btn-soft" id="rules-add">Add</button>\n            <button class="vsp-btn vsp-btn-primary" id="rules-save">Save</button>\n          </div>\n        </div>\n        <div id="rules-msg" style="margin-top:10px; font-size:12px; opacity:.9;"></div>\n      </div>\n\n      <div class="vsp-card" style="padding:0; overflow:auto;">\n        <table style="width:100%; border-collapse:collapse;">\n          <thead>\n            <tr style="text-align:left; font-size:12px; opacity:.85;">\n              <th style="padding:10px 12px; border-bottom:1px solid rgba(255,255,255,.06);">ID</th>\n              <th style="padding:10px 12px; border-bottom:1px solid rgba(255,255,255,.06);">Match (JSON)</th>\n              <th style="padding:10px 12px; border-bottom:1px solid rgba(255,255,255,.06);">Action</th>\n              <th style="padding:10px 12px; border-bottom:1px solid rgba(255,255,255,.06);">Set (JSON)</th>\n              <th style="padding:10px 12px; border-bottom:1px solid rgba(255,255,255,.06);">Justification</th>\n              <th style="padding:10px 12px; border-bottom:1px solid rgba(255,255,255,.06);">Expires</th>\n              <th style="padding:10px 12px; border-bottom:1px solid rgba(255,255,255,.06);">Ops</th>\n            </tr>\n          </thead>\n          <tbody id="rules-body"></tbody>\n        </table>\n      </div>\n\n      <div class="vsp-card" style="margin:12px 0; padding:14px;">\n        <div style="font-weight:700; margin-bottom:8px;">Raw JSON editor</div>\n        <textarea id="rules-json" spellcheck="false"\n          style="width:100%; min-height:240px; font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
          font-size:12px; padding:12px; border-radius:12px; border:1px solid rgba(255,255,255,.08);
          background:rgba(255,255,255,.03); color:inherit;"></textarea>\n        <div style="margin-top:8px; opacity:.75; font-size:12px;">\n          Tip: bạn có thể sửa JSON trực tiếp rồi bấm <b>Save</b>.\n        </div>\n      </div>\n    `;\n    container.innerHTML = html;\n\n    const tb = $("rules-body");\n    const tx = $("rules-json");\n\n    function rowToInputs(it, idx){\n      const id = it.id || (`ovr_${idx+1}`);\n      const match = it.match || {};\n      const action = it.action || (it.set && Object.keys(it.set).length ? "set" : "suppress");\n      const setObj = it.set || {};\n      const justification = it.justification || "";\n      const expires_at = it.expires_at || (new Date().getFullYear()+1)+"-12-31";\n\n      return `\n        <tr data-idx="${idx}" style="border-bottom:1px solid rgba(255,255,255,.06); font-size:13px;">\n          <td style="padding:10px 12px; white-space:nowrap;">\n            <input data-k="id" value="${esc(id)}"\n              style="width:160px; padding:8px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.08);
              background:rgba(255,255,255,.03); color:inherit;">\n          </td>\n          <td style="padding:10px 12px; min-width:260px;">\n            <textarea data-k="match" spellcheck="false"\n              style="width:360px; min-height:64px; padding:8px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.08);
              background:rgba(255,255,255,.03); color:inherit; font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size:12px;">${esc(JSON.stringify(match, null, 2))}</textarea>\n          </td>\n          <td style="padding:10px 12px; white-space:nowrap;">\n            <select data-k="action" style="padding:8px 10px; border-radius:10px;">\n              ${["suppress","set"].map(x=>`<option value="${x}" ${x===action?"selected":""}>${x}</option>`).join("")}\n            </select>\n          </td>\n          <td style="padding:10px 12px; min-width:260px;">\n            <textarea data-k="set" spellcheck="false"\n              style="width:260px; min-height:64px; padding:8px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.08);
              background:rgba(255,255,255,.03); color:inherit; font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size:12px;">${esc(JSON.stringify(setObj, null, 2))}</textarea>\n          </td>\n          <td style="padding:10px 12px;">\n            <input data-k="justification" value="${esc(justification)}"\n              style="width:260px; padding:8px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.08);
              background:rgba(255,255,255,.03); color:inherit;">\n          </td>\n          <td style="padding:10px 12px; white-space:nowrap;">\n            <input data-k="expires_at" value="${esc(expires_at)}" placeholder="${nowIsoDate()}"\n              style="width:140px; padding:8px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.08);
              background:rgba(255,255,255,.03); color:inherit;">\n          </td>\n          <td style="padding:10px 12px; white-space:nowrap;">\n            <button class="vsp-btn vsp-btn-soft" data-act="del">Delete</button>\n          </td>\n        </tr>\n      `;\n    }\n\n    function syncTextAreaFromState(){\n      if(!tx) return;\n      tx.value = JSON.stringify(toPostPayload(state), null, 2);\n    }\n\n    function syncStateFromTable(){\n      const rows = Array.from(tb.querySelectorAll("tr"));\n      const out = [];\n      for(const r of rows){\n        const get = (k)=>r.querySelector(`[data-k="${k}"]`);\n        const it = {};\n        it.id = (get("id")?.value || "").trim() || undefined;\n        it.action = (get("action")?.value || "").trim() || "suppress";\n        it.justification = (get("justification")?.value || "").trim() || "";\n        it.expires_at = (get("expires_at")?.value || "").trim() || "";\n\n        // JSON fields\n        try { it.match = JSON.parse(get("match")?.value || "{}"); }\n        catch(e){ throw new Error("Bad JSON in match for row id="+(it.id||"(no id)")); }\n        try { it.set = JSON.parse(get("set")?.value || "{}"); }\n        catch(e){ throw new Error("Bad JSON in set for row id="+(it.id||"(no id)")); }\n\n        // normalize: if action=suppress => set can be empty\n        if(it.action === "suppress") {\n          if(!it.match || typeof it.match!=="object") it.match = {};\n          // keep set but it's ok if empty\n        }\n        out.push(it);\n      }\n      state.items = out;\n      syncTextAreaFromState();\n    }\n\n    function syncTableFromState(){\n      tb.innerHTML = items.map((it, idx)=>rowToInputs(it, idx)).join("");\n      syncTextAreaFromState();\n    }\n\n    syncTableFromState();\n    msg("Loaded "+items.length+" overrides.", "ok");\n\n    // events\n    $("rules-add")?.addEventListener("click", ()=>{\n      state.items = state.items || [];\n      state.items.push({\n        id: "ovr_" + (state.items.length+1),\n        match: { tool: "KICS" },\n        action: "set",\n        set: { severity: "LOW" },\n        justification: "False positive / accepted risk",\n        expires_at: (new Date().getFullYear()+1) + "-12-31"\n      });\n      syncTableFromState();\n      msg("Added draft override. Edit then Save.", "ok");\n    });\n\n    $("rules-reload")?.addEventListener("click", async ()=>{\n      msg("Reloading…", "ok");\n      try{\n        const j = normalizeFromApi(await apiGet());\n        state.items = j.items || [];\n        syncTableFromState();\n        msg("Reloaded "+state.items.length+" overrides.", "ok");\n      }catch(e){\n        msg(String(e), "err");\n      }\n    });\n\n    $("rules-save")?.addEventListener("click", async ()=>{\n      try{\n        // If user edited raw JSON, prefer that\n        if(tx && tx.value && tx.value.trim().startsWith("{")){\n          let raw;\n          try { raw = JSON.parse(tx.value); }\n          catch(e){ throw new Error("Raw JSON invalid: "+e); }\n          // accept either {meta,overrides} or {version,items}\n          let st = normalizeFromApi(raw);\n          if(raw && raw.meta && Array.isArray(raw.overrides)) st = {version:1, items: raw.overrides};\n          state.items = st.items || [];\n          // re-render table from state to keep consistent\n          syncTableFromState();\n        } else {\n          syncStateFromTable();\n        }\n\n        const payload = toPostPayload(state);\n        msg("Saving…", "ok");\n        const res = await apiSave(payload);\n        msg("Saved OK. File: " + (res.file||"(unknown)"), "ok");\n      }catch(e){\n        msg(String(e && e.message ? e.message : e), "err");\n      }\n    });\n\n    tb.addEventListener("click", (ev)=>{\n      const t = ev.target;\n      if(!(t instanceof Element)) return;\n      const btn = t.closest ? t.closest('[data-act="del"]') : null;\n      if(!btn) return;\n      const tr = btn.closest("tr");\n      if(!tr) return;\n      tr.remove();\n      try{\n        syncStateFromTable();\n        msg("Deleted row (not saved yet). Click Save.", "ok");\n      }catch(e){\n        msg(String(e), "err");\n      }\n    });\n  }\n\n  async function init(){\n    const root = $("vsp-rules-main") || $("panel-rules") || document.querySelector('[data-panel="rules"]');\n    if(!root){ console.warn("[VSP_RULES] rules pane not found"); return; }\n\n    // Avoid double init\n    if(root.getAttribute("data-vsp-rules-inited")==="1") return;\n    root.setAttribute("data-vsp-rules-inited","1");\n\n    root.innerHTML = '<div class="vsp-card" style="margin:12px 0; padding:14px;">Loading rule overrides…</div>';\n\n    let state = { version: 1, items: [] };\n    try{\n      const j = normalizeFromApi(await apiGet());\n      state.items = j.items || [];\n      render(root, state);\n    }catch(e){\n      root.innerHTML = '<div class="vsp-card" style="margin:12px 0; padding:14px;">' +\n        '<div style="font-weight:800;">Rule Overrides load failed</div>' +\n        '<pre style="white-space:pre-wrap; opacity:.85; font-size:12px;">'+esc(String(e && e.stack ? e.stack : e))+'</pre>' +\n        '</div>';\n    }\n  }\n\n  // Public hook for router\n  window.VSP_RULES_TAB_INIT = init;\n\n  // Init only when hash is #rules\n  function maybe(){\n    const h = (location.hash||"").toLowerCase();\n    if(h.includes("rules")) init();\n  }\n  window.addEventListener("hashchange", maybe);\n  document.addEventListener("DOMContentLoaded", maybe);\n\n  console.log("[VSP_RULE_OVERRIDES_TAB_V1] loaded");\n})();\n\n\n/* ==== END static/js/vsp_rule_overrides_tab_v1.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_dashboard_enhance_v1.js ==== */\n\n// VSP_SAFE_DRILLDOWN_HARDEN_P0_V6\n/* P0_DRILLDOWN_NUKE_V8 */\n\n/* __VSP_DD_HANDLER_WRAP_P0_FINAL: normalize VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 to callable */\n(function(){\n  'use strict';\n\n/* VSP_DD_ART_CALL_V1: commercial stable wrapper (fn OR {open:fn}) */\n(function(){\n  'use strict';\n  if (window.VSP_DD_ART_CALL_V1) return;\n  window.VSP_DD_ART_CALL_V1 = function(){\n    var h = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;\n    var args = Array.prototype.slice.call(arguments);\n    try{\n      if (typeof h === 'function') return h.apply(null, args);\n      if (h && typeof h.open === 'function') return h.open.apply(h, args);\n    }catch(e){\n      try{ console.warn('[VSP][DD_CALL_V1]', e); }catch(_){}\n    }\n    return null;\n  };\n})();\n\n\n  try{\n    var h = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;\n    if (h && typeof h !== 'function'){\n      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){\n        return (window.__VSP_DD_SAFE_CALL__ || function(x){\n          try{\n            var a=[].slice.call(arguments,1);\n            if (typeof x==='function') return x.apply(null,a);\n            if (x && typeof x.open==='function') return x.open.apply(x,a);\n          }catch(_){}\n          return null;\n        }).apply(null, [h].concat([].slice.call(arguments)));\n      };\n      try{ console.log('[VSP][P0] drilldown handler wrapped (obj->fn)'); }catch(_){}\n    }\n  }catch(e){}\n})();\n\n(function(){\n  try{\n    if (typeof window === "undefined") return;\n\n\n/* VSP_FIX_DRILLDOWN_ARTIFACTS_NOT_FUNCTION_P0_V2\n * Fix: TypeError __VSP_DD_ART_CALL__(VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2, ...) is not a function\n * Normalize BEFORE first use:\n *   - if function: keep\n *   - if object with .open(): wrap as function(arg)->obj.open(arg)\n *   - else: no-op (never throw)\n */\n(function(){\n  'use strict';\n  \n\n\n\n/* VSP_FIX_DRILLDOWN_CALLSITE_P0_V5: safe-call drilldown artifacts (function OR object.open) */\nfunction __VSP_DD_ART_CALL__(h, ...args) {\n  try {\n    if (typeof h === 'function') return h(...args);\n    if (h && typeof h.open === 'function') return h.open(...args);\n  } catch(e) { try{console.warn('[VSP][DD_SAFE]', e);}catch(_e){} }\n  return null;\n}\n\n/* VSP_FIX_DRILLDOWN_CALLSITE_P0_V3: safe-call for drilldown artifacts (function OR object.open) */\nfunction __VSP_DD_ART_CALL__(h, ...args) {\n  try {\n    if (typeof h === 'function') return h(...args);\n    if (h && typeof h.open === 'function') return h.open(...args);\n  } catch (e) {\n    try { console.warn('[VSP][DD_SAFE] call failed', e); } catch (_e) {}\n  }\n  return null;\n}\n\nif (window.__VSP_FIX_DRILLDOWN_ARTIFACTS_NOT_FUNCTION_P0_V2) return;\n  window.__VSP_FIX_DRILLDOWN_ARTIFACTS_NOT_FUNCTION_P0_V2 = 1;\n\n  function normalize(v){\n    if (typeof v === 'function') return v;\n    if (v && typeof v.open === 'function') {\n      const obj = v;\n      const fn = function(arg){ try { return obj.open(arg); } catch(e){ console.warn('[VSP][DD_FIX] open() failed', e); return null; } };\n      fn.__wrapped_from_object = true;\n      return fn;\n    }\n    const noop = function(_arg){ return null; };\n    noop.__noop = true;\n    return noop;\n  }\n\n  try {\n    // trap future assignments\n    let _val = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;\n    Object.defineProperty(window, 'VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2', {\n      configurable: true, enumerable: true,\n      get: function(){ return _val; },\n      set: function(v){ _val = normalize(v); }\n    });\n    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = _val;\n  } catch(e) {\n    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = normalize(window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2);\n  }\n})();\n\n    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {\n      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){\n        try{ console.info("[VSP][P0] drilldown window stub called"); }catch(_){}\n        return {open(){},show(){},close(){},destroy(){}};\n      };\n    }\n  }catch(_){}\n})();\n\n/* P0_DRILLDOWN_STUB_V6 */\n(function(){\n  try{\n    if (typeof window === "undefined") return;\n    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {\n      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){\n        try{ console.info("[VSP_DASH][P0] drilldown window stub called"); }catch(_){}\n        return {open(){},show(){},close(){},destroy(){}};\n      };\n    }\n  }catch(_){}\n})();\n\n/* P0_DRILLDOWN_CALL_V3 */\n(function(){\n  try{\n    if (typeof window === "undefined") return;\n\n    // Stub always returns an object with safe methods\n    window.__VSP_P0_DRILLDOWN_STUB = window.__VSP_P0_DRILLDOWN_STUB || function(){\n      try{ console.info("[VSP_DASH][P0] drilldown stub called"); }catch(_){}\n      return { open(){}, show(){}, close(){}, destroy(){} };\n    };\n\n    // Ensure window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 is callable\n    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {\n      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = window.__VSP_P0_DRILLDOWN_STUB;\n      try{ console.info("[VSP_DASH][P0] drilldown forced stub (window)"); }catch(_){}\n    }\n\n    // Stable call entry (never throws)\n    window.__VSP_P0_DRILLDOWN_CALL = window.__VSP_P0_DRILLDOWN_CALL || function(){\n      try{\n        const fn = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;\n        if (typeof fn === "function") return fn.apply(window, arguments);\n      }catch(_){}\n      try{\n        return window.__VSP_P0_DRILLDOWN_STUB.apply(window, arguments);\n      }catch(_){}\n      return { open(){}, show(){}, close(){}, destroy(){} };\n    };\n  }catch(_){}\n})();\n\n/* VSP_P0_DRILLDOWN_CALL_V2: prevent red console when drilldown is missing */\n(function(){\n  try{\n    if (typeof window === "undefined") return;\n\n    // ensure window function exists early (before any local capture)\n    if (typeof window.__VSP_P0_DRILLDOWN_STUB !== "function") {\n      window.__VSP_P0_DRILLDOWN_STUB = function(){\n        try{ console.info("[VSP_DASH][P0] drilldown stub called"); }catch(_){}\n        return { open(){}, show(){}, close(){}, destroy(){} };\n      };\n    }\n    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {\n      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = window.__VSP_P0_DRILLDOWN_STUB;\n      try{ console.info("[VSP_DASH][P0] drilldown forced stub (window)"); }catch(_){}\n    }\n\n    // stable caller: always a function\n    if (typeof window.__VSP_P0_DRILLDOWN_CALL_V2 !== "function") {\n      window.__VSP_P0_DRILLDOWN_CALL_V2 = function(){\n        try{\n          var fn = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;\n          if (typeof fn === "function") return fn.apply(window, arguments);\n        }catch(_){}\n        try{\n          var stub = window.__VSP_P0_DRILLDOWN_STUB;\n          if (typeof stub === "function") return stub.apply(window, arguments);\n        }catch(_){}\n        return { open(){}, show(){}, close(){}, destroy(){} };\n      };\n    }\n  }catch(_){}\n})();\n\n/* P0_GUARD_GLOBAL_V1 */\n// Define global guard so any callsite can see it (prevents ReferenceError)\n(function(){\n  try{\n    if (typeof window === "undefined") return;\n\n    window.VSP_DASH_IS_ACTIVE_P0 = window.VSP_DASH_IS_ACTIVE_P0 || function(){\n      try{\n        const h = (location.hash || "").toLowerCase();\n        if (!h || h === "#" || h === "#dashboard") return true;\n        return false;\n      }catch(_){ return false; }\n    };\n\n    window.VSP_DASH_P0_GUARD = window.VSP_DASH_P0_GUARD || function(reason){\n      try{\n        if (!window.VSP_DASH_IS_ACTIVE_P0()){\n          try{ console.info("[VSP_DASH][P0] skip:", reason, "hash=", location.hash); }catch(_){}\n          return false;\n        }\n        return true;\n      }catch(_){ return true; }\n    };\n\n    // Also provide plain global function names (some code calls them directly)\n    if (typeof window.VSP_DASH_P0_GUARD === "function") {\n      window.VSP_DASH_P0_GUARD_NAME = "ok";\n    }\n  }catch(_){}\n})();\n\n// Plain-name wrappers (avoid ReferenceError even if code calls VSP_DASH_P0_GUARD directly)\nfunction VSP_DASH_IS_ACTIVE_P0(){ try{ return (window && window.VSP_DASH_IS_ACTIVE_P0) ? window.VSP_DASH_IS_ACTIVE_P0() : true; }catch(_){ return true; } }\nfunction VSP_DASH_P0_GUARD(reason){ try{ return (window && window.VSP_DASH_P0_GUARD) ? window.VSP_DASH_P0_GUARD(reason) : true; }catch(_){ return true; } }\n\n// === VSP_CHARTS_ENGINE_SHIM_V1 ===\n(function(){\n  // Always provide a safe resolver so dashboard never crashes on missing symbol names.\n  function _findChartsEngineShim(){\n    return (\n      window.VSP_CHARTS_ENGINE_V3 ||\n      window.VSP_CHARTS_V3 ||\n      window.VSP_CHARTS_PRETTY_V3 ||\n      window.VSP_DASH_CHARTS_V3 ||\n      window.VSP_CHARTS_ENGINE_V2 ||\n      window.VSP_CHARTS_V2 ||\n      window.VSP_CHARTS_ENGINE ||\n      window.VSP_CHARTS ||\n      null\n    );\n  }\n  if (typeof window.findChartsEngine !== 'function') {\n    window.findChartsEngine = _findChartsEngineShim;\n  }\n})();\n\n// === VSP_FIND_CHARTS_ENGINE_FALLBACK_V1 ===\nif (typeof window.findChartsEngine !== 'function') {\n  window.findChartsEngine = function () {\n    try {\n      // Prefer explicit exported engines\n      if (window.VSP_DASH_CHARTS_ENGINE) return window.VSP_DASH_CHARTS_ENGINE;\n      if (window.VSP_DASH_CHARTS_V3) return window.VSP_DASH_CHARTS_V3;\n      if (window.VSP_DASH_CHARTS_V2) return window.VSP_DASH_CHARTS_V2;\n\n      // Heuristic: look for known globals from pretty charts scripts\n      var cand = [\n        window.vsp_dashboard_charts_v3,\n        window.vsp_dashboard_charts_v2,\n        window.VSP_CHARTS_V3,\n        window.VSP_CHARTS_V2\n      ].filter(Boolean)[0];\n\n      return cand || null;\n    } catch (e) { return null; }\n  };\n}\n// === END VSP_FIND_CHARTS_ENGINE_FALLBACK_V1 ===\n(function () {\n  // VSP 2025 – Dashboard enhance V4 (clean, no patch lỗi)\n  console.log('[VSP_DASH] vsp_dashboard_enhance_v1.js (V4 clean) loaded');\n\n  function onReady(fn) {\n    if (document.readyState === 'loading') {\n      document.addEventListener('DOMContentLoaded', fn);\n    } else {\n      fn();\n    }\n  }\n\n  function safeText(id, value) {\n    var el = document.getElementById(id);\n    if (!el) return;\n    el.textContent = value;\n  }\n\n  function fetchDashboard() {\n    return fetch('/api/vsp/dashboard_v3', {\n      credentials: 'same-origin'\n    }).then(function (r) {\n      if (!r.ok) throw new Error('HTTP ' + r.status);\n      return r.json();\n    });\n  }\n\n  function fillKpis(data) {\n    if (!data || typeof data !== 'object') return;\n    var bySeverity = data.by_severity || {};\n    var total = data.total_findings != null\n      ? data.total_findings\n      : (bySeverity.CRITICAL || 0) + (bySeverity.HIGH || 0) +\n        (bySeverity.MEDIUM || 0) + (bySeverity.LOW || 0) +\n        (bySeverity.INFO || 0) + (bySeverity.TRACE || 0);\n\n    safeText('vsp-kpi-total-findings', total);\n    safeText('vsp-kpi-critical', bySeverity.CRITICAL != null ? bySeverity.CRITICAL : 0);\n    safeText('vsp-kpi-high',     bySeverity.HIGH     != null ? bySeverity.HIGH     : 0);\n    safeText('vsp-kpi-medium',   bySeverity.MEDIUM   != null ? bySeverity.MEDIUM   : 0);\n    safeText('vsp-kpi-low',      bySeverity.LOW      != null ? bySeverity.LOW      : 0);\n    safeText('vsp-kpi-info',     bySeverity.INFO     != null ? bySeverity.INFO     : 0);\n    safeText('vsp-kpi-trace',    bySeverity.TRACE    != null ? bySeverity.TRACE    : 0);\n\n    if (data.security_posture_score != null) {\n      safeText('vsp-kpi-security-score', data.security_posture_score);\n    }\n\n    safeText('vsp-kpi-top-tool',   data.top_risky_tool       || 'N/A');\n    safeText('vsp-kpi-top-cwe',    data.top_impacted_cwe     || data.top_cwe || 'N/A');\n    safeText('vsp-kpi-top-module', data.top_vulnerable_module || 'N/A');\n\n    var gate = data.ci_gate_status || data.ci_gate || {};\n    var gateLabel = gate.label || gate.status || 'N/A';\n    var gateDesc  = gate.description || 'Gate dựa trên CRITICAL/HIGH, score & coverage.';\n    safeText('vsp-kpi-ci-gate-status',      gateLabel);\n    safeText('vsp-kpi-ci-gate-status-desc', gateDesc);\n  }\n\n  function hydrateDashboard(data) {\n    try {\n      fillKpis(data);\n\n      if (window.VSP_CHARTS_V3 && typeof window.VSP_CHARTS_V3.updateFromDashboard === 'function') {\n        window.VSP_CHARTS_V3.updateFromDashboard(data);\n      } else if (window.VSP_CHARTS_V2 && typeof window.VSP_CHARTS_V2.updateFromDashboard === 'function') {\n        window.VSP_CHARTS_V2.updateFromDashboard(data);\n      } else {\n        console.debug('[VSP_DASH] No charts engine V2/V3 found – only KPIs filled. (will retry)');\n      }\n\n      console.log('[VSP_DASH] Dashboard hydrated OK (V4 clean).');\n    } catch (e) {\n      console.error('[VSP_DASH] Error hydrating dashboard:', e);\n    }\n  }\n\n  window.hydrateDashboard = hydrateDashboard;\n\n  onReady(function () {\n    var pane = document.getElementById('vsp-dashboard-main');\n    if (!pane) {\n      console.log('[VSP_DASH] No dashboard pane found, skip auto fetch.');\n      return;\n    }\n    console.log('[VSP_DASH] Hydrating dashboard (auto fetch)…');\n  if (!VSP_DASH_P0_GUARD("hydrate")) { return; }\n    fetchDashboard()\n      .then(function (data) {\n        console.log('[VSP_DASH] dashboard_v3 data =', data);\n        hydrateDashboard(data);\n      })\n      .catch(function (err) {\n        console.error('[VSP_DASH] Failed to load /api/vsp/dashboard_v3:', err);\n      });\n  });\n\n})();\n\n\n// === VSP_DASH_CHARTS_RETRY_V1 ===\n(function(){\n  try{\n    let tries = 0;\n    function tryHydrate(){\n      tries++;\n      const eng = window.VSP_CHARTS_V3 || window.VSP_CHARTS_PRETTY_V3 || window.VSP_CHARTS_ENGINE_V3;\n      if (eng && typeof eng.hydrate === 'function' && window.__VSP_LAST_DASH_DATA__){\n        eng.hydrate(window.__VSP_LAST_DASH_DATA__);\n        console.log('[VSP_DASH] charts hydrated via retry');\n        return;\n      }\n      if (tries < 8) setTimeout(tryHydrate, 300);\n    }\n    setTimeout(tryHydrate, 300);\n  }catch(e){}\n})();\n// === END VSP_DASH_CHARTS_RETRY_V1 ===\n\n\n// === VSP_DASH_CHARTS_RETRY_V2 ===\n(function(){\n  try{\n    let tries = 0;\n    function tick(){\n      tries++;\n      const eng = findChartsEngine();\n      if (eng && window.__VSP_LAST_DASH_DATA__){\n        try{\n          eng.hydrate(window.__VSP_LAST_DASH_DATA__);\n          console.log('[VSP_DASH] charts hydrated via retry v2');\n          return;\n        }catch(e){}\n      }\n      if (tries < 8) setTimeout(tick, 350);\n    }\n    setTimeout(tick, 350);\n  }catch(e){}\n})();\n// === END VSP_DASH_CHARTS_RETRY_V2 ===\n\n\n// === VSP_DASH_USE_DASH_V3_AND_INIT_CHARTS_V1 ===\n(function(){\n  try {\n    if (window.__VSP_DASH_INIT_CHARTS_V1) return;\n    window.__VSP_DASH_INIT_CHARTS_V1 = true;\n\n    function _vspGetChartsEngine() {\n      return window.VSP_CHARTS_ENGINE_V3 || window.VSP_CHARTS_ENGINE_V2 || null;\n    }\n\n    window.__VSP_DASH_TRY_INIT_CHARTS_V1 = function(dash, reason) {\n      try {\n        if (dash) window.__VSP_DASH_LAST_DATA_V3 = dash;\n        var eng = _vspGetChartsEngine();\n        if (!eng || !eng.initAll) return false;\n        var d = dash || window.__VSP_DASH_LAST_DATA_V3;\n        if (!d) return false;\n        var ok = eng.initAll(d);\n        console.log("[VSP_DASH] charts initAll via", reason || "unknown", "=>", ok);\n        return !!ok;\n      } catch (e) {\n        console.warn("[VSP_DASH] charts init failed", e);\n        return false;\n      }\n    };\n\n    // Listen for charts-ready (late engine load)\n    window.addEventListener("vsp:charts-ready", function(ev){\n      setTimeout(function(){\n        window.__VSP_DASH_TRY_INIT_CHARTS_V1(null, "charts-ready");\n      }, 0);\n    });\n  } catch(e) {\n    console.warn("[VSP_DASH] init-charts patch failed", e);\n  }\n})();\n\n// === VSP_ENHANCE_WAIT_CHARTS_READY_V1 ===\n\n(function(){\n  try{\n    if (window.__VSP_ENHANCE_WAIT_CHARTS_READY_V1) return;\n    window.__VSP_ENHANCE_WAIT_CHARTS_READY_V1 = true;\n\n    function pickEngine(){\n      return window.VSP_CHARTS_ENGINE_V3 || window.VSP_CHARTS_ENGINE_V2 || window.VSP_CHARTS_ENGINE || null;\n    }\n\n    function tryInit(){\n      var eng = pickEngine();\n      var d = window.__VSP_DASH_LAST_DATA_V3 || window.__VSP_DASH_LAST_DATA || window.__VSP_DASH_LAST_DATA_ANY || null;\n      if (!eng || !eng.initAll || !d) return false;\n      try{\n        eng.initAll(d);\n        return true;\n      }catch(e){\n        return false;\n      }\n    }\n\n    window.addEventListener('vsp:charts-ready', function(){\n      // chỉ init khi đã có data (dashboard fetch xong)\n      tryInit();\n    });\n\n    // nếu engine đã có sẵn thì thử init luôn (không warn)\n    tryInit();\n  }catch(e){}\n})();\n\n\n\n// === VSP_UI_KPI_DRILLDOWN_V1 ===\n(function(){\n  const KEY = "vsp_ds_drill_url_v1";\n\n  async function loadDashLatest(){\n    try{\n      const r = await fetch("/api/vsp/dashboard_latest_v1", {credentials:"same-origin"});\n      const j = await r.json();\n      window.__VSP_DASH_LATEST_V1 = j;\n      return j;\n    }catch(e){\n      console.warn("[KPI_DRILLDOWN] loadDashLatest failed", e);\n      return null;\n    }\n  }\n\n  function _setDrillUrl(url){\n    try{ sessionStorage.setItem(KEY, url); }catch(e){}\n  }\n\n  function openDrill(url){\n    if(!url) return;\n    _setDrillUrl(url);\n\n    // best-effort: switch tab by hash\n    try{\n      if(!String(location.hash||"").toLowerCase().includes("datasource")){\n        location.hash = "#datasource";\n        // kick router if it listens\n        setTimeout(()=>{ try{ window.dispatchEvent(new Event("hashchange")); }catch(e){} }, 50);\n      }\n    }catch(e){}\n\n    // if Data Source JS installed hook -> use it\n    if(typeof window.VSP_DS_APPLY_DRILL_URL_V1 === "function"){\n      try{ window.VSP_DS_APPLY_DRILL_URL_V1(url); return; }catch(e){}\n    }\n\n    // fallback: open API in new tab (always works)\n    try{ window.open(url, "_blank"); }catch(e){}\n  }\n\n  function bindClicks(dash){\n    if(!dash || !dash.links) return;\n\n    const sevLinks = (dash.links.severity || {});\n    const allUrl   = dash.links.all;\n\n    const nodes = Array.from(document.querySelectorAll("a,button,div,section,article,span"))\n      .filter(el=>{\n        const txt = (el.innerText||"").trim();\n        return txt && txt.length > 0 && txt.length < 160;\n      });\n\n    function attachByKeyword(keywordUpper, url, title){\n      if(!url) return;\n      for(const el of nodes){\n        const txt = (el.innerText||"").toUpperCase();\n        if(!txt.includes(keywordUpper)) continue;\n        if(el.__vsp_drill_attached) continue;\n        el.__vsp_drill_attached = true;\n        el.style.cursor = "pointer";\n        el.title = title;\n        el.addEventListener("click", (ev)=>{\n          // allow user open normally with ctrl/cmd\n          if(ev && (ev.ctrlKey || ev.metaKey || ev.shiftKey)) return;\n          try{ ev.preventDefault(); }catch(e){}\n          openDrill(url);\n        });\n      }\n    }\n\n    // severity KPI cards (by keyword)\n    ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"].forEach(sev=>{\n      attachByKeyword(sev, sevLinks[sev], `Drilldown → ${sev}`);\n    });\n\n    // total findings KPI (heuristic)\n    if(allUrl){\n      for(const el of nodes){\n        const txt = (el.innerText||"").toUpperCase();\n        const hit = (txt.includes("TOTAL") && (txt.includes("FIND") || txt.includes("FINDINGS"))) || txt.includes("TOTAL FINDINGS");\n        if(!hit) continue;\n        if(el.__vsp_drill_total) continue;\n        el.__vsp_drill_total = true;\n        el.style.cursor = "pointer";\n        el.title = "Drilldown → ALL findings";\n        el.addEventListener("click", (ev)=>{\n          if(ev && (ev.ctrlKey || ev.metaKey || ev.shiftKey)) return;\n          try{ ev.preventDefault(); }catch(e){}\n          openDrill(allUrl);\n        });\n      }\n    }\n\n    // expose helper for manual use\n    window.VSP_DASH_OPEN_DRILL_V1 = openDrill;\n    console.log("[KPI_DRILLDOWN] bound", {rid: dash.rid, hasLinks: !!dash.links});\n  }\n\n  window.addEventListener("load", async ()=>{\n    const dash = await loadDashLatest();\n    // wait a bit so DOM cards exist\n    setTimeout(()=>bindClicks(dash), 600);\n  });\n})();\n\n\n\n// === VSP_UI_DRILL_PANEL_V1 ===\n(function(){\n  const KEY = "vsp_ds_drill_url_v1";\n\n  function setDrillUrl(url){\n    try{ sessionStorage.setItem(KEY, url); }catch(e){}\n  }\n  function gotoDatasource(){\n    const h = String(location.hash||"");\n    if(h.startsWith("#vsp4-")) location.hash = "#vsp4-datasource";\n    else location.hash = "#datasource";\n    try{ window.dispatchEvent(new Event("hashchange")); }catch(e){}\n  }\n  async function dashLatest(){\n    const r = await fetch("/api/vsp/dashboard_latest_v1", {credentials:"same-origin"});\n    return await r.json();\n  }\n\n  function ensurePanel(d){\n    const id="vsp_drill_panel_v1";\n    if(document.getElementById(id)) return;\n\n    const wrap=document.createElement("div");\n    wrap.id=id;\n    wrap.style.position="fixed";\n    wrap.style.right="18px";\n    wrap.style.bottom="18px";\n    wrap.style.zIndex="9999";\n    wrap.style.padding="10px";\n    wrap.style.borderRadius="14px";\n    wrap.style.border="1px solid rgba(255,255,255,.10)";\n    wrap.style.background="rgba(2,6,23,.78)";\n    wrap.style.backdropFilter="blur(10px)";\n    wrap.style.boxShadow="0 10px 30px rgba(0,0,0,.35)";\n    wrap.style.fontSize="12px";\n    wrap.style.color="rgba(255,255,255,.85)";\n    wrap.innerHTML = `\n      <div style="font-weight:700;margin-bottom:6px;">Drilldown</div>\n      <div style="display:flex;gap:8px;flex-wrap:wrap;">\n        <button id="vsp_drill_total" style="padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.06);color:#fff;cursor:pointer;">TOTAL</button>\n        <button id="vsp_drill_critical" style="padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.06);color:#fff;cursor:pointer;">CRITICAL</button>\n        <button id="vsp_drill_high" style="padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.06);color:#fff;cursor:pointer;">HIGH</button>\n      </div>\n      <div style="opacity:.65;margin-top:6px;">(opens Data Source)</div>\n    `;\n    document.body.appendChild(wrap);\n\n    const links = (d && d.links) ? d.links : {};\n    const sev = (links.severity)||{};\n    function bind(btnId, url){\n      const b=document.getElementById(btnId);\n      if(!b) return;\n      b.onclick = ()=>{\n        if(!url){ console.warn("[DRILL] missing url for", btnId); return; }\n        setDrillUrl(url);\n        gotoDatasource();\n        if(typeof window.VSP_DS_APPLY_DRILL_URL_V1==="function"){\n          try{ window.VSP_DS_APPLY_DRILL_URL_V1(url); }catch(e){}\n        }\n        console.log("[DRILL] open", url);\n      };\n    }\n    bind("vsp_drill_total", links.all);\n    bind("vsp_drill_critical", sev.CRITICAL);\n    bind("vsp_drill_high", sev.HIGH);\n  }\n\n  window.addEventListener("load", async ()=>{\n    try{\n      const d = await dashLatest();\n      window.__VSP_DASH_LATEST_V1 = d;\n      ensurePanel(d);\n    }catch(e){\n      console.warn("[DRILL_PANEL] failed", e);\n    }\n  });\n})();\n\n// === VSP_P2_DRILL_ROUTER_V1 ===\n// Drill router: click elements with data-drill -> switch tab datasource + apply filters\n(function(){\n  function parseHashParams(){\n    let h = (location.hash || "").replace(/^#\/?/,"");\n    if (!h) return {};\n    const out = {};\n    for (const part of h.split("&")){\n      if (!part) continue;\n      const [k,v] = part.split("=",2);\n      if (!k) continue;\n      out[decodeURIComponent(k)] = decodeURIComponent(v||"");\n    }\n    return out;\n  }\n\n  function buildHash(tab, filters){\n    const sp = new URLSearchParams();\n    sp.set("tab", tab || "datasource");\n    for (const [k,v] of Object.entries(filters||{})){\n      if (v === undefined || v === null) continue;\n      const sv = String(v).trim();\n      if (!sv) continue;\n      sp.set(k, sv);\n    }\n    return "#" + sp.toString();\n  }\n\n  function switchToDatasourceTab(){\n    // Try click datasource tab button if exists\n    const btn = document.querySelector("#tab-datasource, [data-tab-btn='datasource'], a[href*='datasource']");\n    if (btn && btn.click) btn.click();\n  }\n\n  function applyDatasource(filters){\n    // Set hash first (so reload preserves)\n    const h = buildHash("datasource", filters||{});\n    if (location.hash !== h) location.hash = h;\n\n    // then call sink if available\n    const sink = window.VSP_DATASOURCE_APPLY_FILTERS_V1;\n    if (typeof sink === "function"){\n      try{ sink(filters||{}, {noHashSync:true}); }catch(e){}\n    }\n  }\n\n  function handleDrillClick(e){\n    const a = e.target.closest("[data-drill]");\n    if (!a) return;\n    e.preventDefault();\n    let val = a.getAttribute("data-drill") || "";\n    // accept JSON {"sev":"HIGH"} or query "sev=HIGH&tool=semgrep"\n    let filters = {};\n    try{\n      if (val.trim().startsWith("{")) filters = JSON.parse(val);\n      else{\n        const sp = new URLSearchParams(val.replace(/^#\/?/,""));\n        sp.forEach((v,k)=>{ filters[k]=v; });\n      }\n    }catch(_){\n      filters = {};\n    }\n    switchToDatasourceTab();\n    applyDatasource(filters);\n  }\n\n  function onHashChange(){\n    const hp = parseHashParams();\n    if ((hp.tab||"") !== "datasource") return;\n    const f = Object.assign({}, hp);\n    delete f.tab;\n    const sink = window.VSP_DATASOURCE_APPLY_FILTERS_V1;\n    if (typeof sink === "function"){\n      sink(f, {noHashSync:true});\n    }\n  }\n\n  function bind(){\n    // delegate click drill\n    if (!document.body._vspDrillBound){\n      document.body._vspDrillBound = true;\n      document.body.addEventListener("click", handleDrillClick);\n    }\n    window.addEventListener("hashchange", onHashChange);\n    // initial\n    onHashChange();\n  }\n\n  if (document.readyState === "loading"){\n    document.addEventListener("DOMContentLoaded", bind);\n  }else{\n    bind();\n  }\n})();\n\n// === VSP_P2_AUTOBIND_KPI_DRILL_V1 ===\n// Auto bind drilldown for KPI cards (clickable commercial)\n// - Uses dashboard_latest_v1.links if present\n// - Fallback binds severity labels CRITICAL/HIGH/MEDIUM/LOW/INFO/TRACE\n(function(){\n  const SEVS = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];\n\n  function qs(sel, root){ return (root||document).querySelector(sel); }\n  function qsa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }\n\n  function norm(s){ return String(s||"").trim().toUpperCase(); }\n\n  function parseDrillToQuery(drill){\n    // drill may be absolute/relative url to datasource, or a query-like string\n    if (!drill) return "";\n    let s = String(drill).trim();\n    // if full URL, take hash or query\n    try{\n      if (s.startsWith("http")){\n        const u = new URL(s);\n        if (u.hash && u.hash.length > 1) return u.hash.replace(/^#\/?/,"");\n        if (u.search && u.search.length > 1) return u.search.replace(/^\?/,"");\n      }\n    }catch(_){}\n    // if starts with #...\n    s = s.replace(/^#\/?/,"");\n    // remove leading vsp4 path fragments\n    s = s.replace(/^\/?vsp4\??/,"").replace(/^\?/,"");\n    return s;\n  }\n\n  async function fetchDash(){\n    const r = await fetch("/api/vsp/dashboard_latest_v1", {cache:"no-store"});\n    return await r.json();\n  }\n\n  function bindEl(el, query){\n    if (!el || !query) return;\n    // do not double bind\n    if (el.getAttribute("data-drill")) return;\n    el.setAttribute("data-drill", query);\n    el.style.cursor = "pointer";\n    el.title = el.title || "Click to drilldown";\n  }\n\n  function findKpiCandidates(){\n    // broad selectors; harmless if none\n    const sels = [\n      ".vsp-kpi-card", ".kpi-card", ".kpi", ".vsp-card",\n      "[data-kpi]", "[data-kpi-card]", "[data-role='kpi']"\n    ];\n    const out = [];\n    for (const s of sels){\n      qsa(s).forEach(x=>out.push(x));\n    }\n    // fallback: any card-like divs in dashboard area\n    const dash = qs("#vsp-dashboard-main") || qs("#tab-dashboard") || document.body;\n    qsa("div", dash).forEach(d=>{\n      const txt = norm(d.innerText||"");\n      if (SEVS.some(s=>txt.includes(s)) && (d.offsetWidth>80 && d.offsetHeight>40)){\n        out.push(d);\n      }\n    });\n    // unique\n    return Array.from(new Set(out));\n  }\n\n  function bestEffortBindFromLinks(links){\n    // expected shapes:\n    // links: { severity: {HIGH:"tab=datasource&sev=HIGH"...}, all:"...", suppressed:"..." }\n    if (!links || typeof links !== "object") return false;\n    const kpis = findKpiCandidates();\n    let bound = 0;\n\n    // bind severity-based\n    for (const sev of SEVS){\n      const drill = links?.severity?.[sev] || links?.["severity."+sev] || links?.[sev] || null;\n      if (!drill) continue;\n      const q = parseDrillToQuery(drill);\n      if (!q) continue;\n      for (const el of kpis){\n        const txt = norm(el.innerText||"");\n        if (txt.includes(sev)){\n          bindEl(el, q);\n          bound++;\n        }\n      }\n    }\n\n    // bind "all" if present\n    if (links.all){\n      const q = parseDrillToQuery(links.all);\n      if (q){\n        for (const el of kpis){\n          const txt = norm(el.innerText||"");\n          if (txt.includes("TOTAL") || txt.includes("ALL") || txt.includes("FINDINGS")){\n            bindEl(el, q);\n            bound++;\n          }\n        }\n      }\n    }\n    return bound > 0;\n  }\n\n  function fallbackBindSev(){\n    const kpis = findKpiCandidates();\n    let bound = 0;\n    for (const sev of SEVS){\n      const q = "tab=datasource&sev=" + encodeURIComponent(sev) + "&limit=200";\n      for (const el of kpis){\n        const txt = norm(el.innerText||"");\n        if (txt.includes(sev)){\n          bindEl(el, q);\n          bound++;\n        }\n      }\n    }\n    return bound>0;\n  }\n\n  async function init(){\n    try{\n      const j = await fetchDash();\n      const links = j?.links || j?.drilldown || j?.drill || null;\n      const ok = bestEffortBindFromLinks(links);\n      if (!ok) fallbackBindSev();\n    }catch(e){\n      fallbackBindSev();\n    }\n  }\n\n  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);\n  else init();\n})();\n\n\n\n// === VSP_P2_FORCE_8TOOLS_V1 ===\n// Force Gate Summary to show 8 tools (commercial). Missing tool => NOT_RUN/0.\n// Also capture latest /api/vsp/run_status_v2 JSON via fetch clone.\n(function(){\n  try{\n    if (window.__VSP_P2_FORCE_8TOOLS_V1_INSTALLED) return;\n    window.__VSP_P2_FORCE_8TOOLS_V1_INSTALLED = true;\n\n    const TOOL_ORDER = ["BANDIT","CODEQL","GITLEAKS","GRYPE","KICS","SEMGREP","SYFT","TRIVY"];\n    window.__VSP_TOOL_ORDER = TOOL_ORDER;\n\n    const origFetch = window.fetch;\n    window.fetch = async function(){\n      const resp = await origFetch.apply(this, arguments);\n      try{\n        const u = (typeof arguments[0] === "string") ? arguments[0] : (arguments[0] && arguments[0].url) || "";\n        if (u.includes("/api/vsp/run_status_v2")) {\n          resp.clone().json().then(j => {\n            window.__VSP_LAST_STATUS_V2 = j;\n            try { window.__VSP_RENDER_GATE_8TOOLS(); } catch(e){}\n          }).catch(()=>{});\n        }\n      }catch(e){}\n      return resp;\n    };\n\n    function pickToolObj(st, T){\n      if (!st || typeof st !== "object") return null;\n      const k = T.toLowerCase();\n      return st[k + "_summary"] || st[k] || (st.tools && (st.tools[T] || st.tools[k])) || null;\n    }\n\n    function normVerdict(v){\n      v = String(v || "").toUpperCase();\n      if (!v) return "NOT_RUN";\n      return v;\n    }\n\n    window.__VSP_RENDER_GATE_8TOOLS = function(){\n      const st = window.__VSP_LAST_STATUS_V2;\n      // find a plausible gate summary container\n      const box =\n        document.querySelector("#vsp-gate-summary") ||\n        document.querySelector("#gate-summary") ||\n        document.querySelector("[data-vsp-gate-summary]") ||\n        document.querySelector(".vsp-gate-summary") ||\n        document.querySelector("section#vsp-pane-dashboard .vsp-card .vsp-gate") ||\n        null;\n      if (!box) return;\n\n      // create or find list container\n      let list = box.querySelector(".vsp-gate-list");\n      if (!list) {\n        list = document.createElement("div");\n        list.className = "vsp-gate-list";\n        box.appendChild(list);\n      }\n\n      const rows = TOOL_ORDER.map(T => {\n        const o = pickToolObj(st, T) || {};\n        const verdict = normVerdict(o.verdict || o.status || o.result || (st && st[(T.toLowerCase()) + "_verdict"]) || "");\n        const total = (o.total != null) ? Number(o.total) : Number((st && st[(T.toLowerCase()) + "_total"]) || 0) || 0;\n        const pillCls = "vsp-pill vsp-pill-" + verdict.toLowerCase();\n\n        return `\n          <div class="vsp-gate-row" style="display:flex;align-items:center;justify-content:space-between;padding:6px 0;border-top:1px solid rgba(255,255,255,.06)">\n            <div style="font-weight:650;letter-spacing:.2px">${T}</div>\n            <div style="display:flex;gap:10px;align-items:center">\n              <span class="${pillCls}">${verdict}</span>\n              <span style="opacity:.75">total: ${total}</span>\n            </div>\n          </div>`;\n      }).join("");\n\n      list.innerHTML = rows;\n    };\n\n    // attempt render once later (in case status fetched before patch)\n    setTimeout(()=>{ try{ window.__VSP_RENDER_GATE_8TOOLS(); }catch(e){} }, 1200);\n  }catch(e){}\n})();\n // === /VSP_P2_FORCE_8TOOLS_V1 ===\n\n\n\n\n// === VSP_UI_DRILLDOWN_AND_EXPORTPROBE_V1 ===\n(function(){\n  'use strict';\n\n  \n  \n  \n  \n  \n  \n  \n\n\n/* VSP_DRILLDOWN_ARTIFACTS_NORMALIZE_P0_V1\n * Fix: Uncaught TypeError: __VSP_DD_ART_CALL__(VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2, ...) is not a function\n * Normalize window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2:\n *  - if function: keep\n *  - if object with .open(): wrap to function\n *  - if missing: provide no-op function (never throw)\n */\n(function(){\n  'use strict';\n  if (window.__VSP_DRILLDOWN_ARTIFACTS_NORMALIZE_P0_V1) return;\n  window.__VSP_DRILLDOWN_ARTIFACTS_NORMALIZE_P0_V1 = 1;\n\n  function normalize(v){\n    if (typeof v === 'function') return v;\n    if (v && typeof v.open === 'function'){\n      const obj = v;\n      const fn = function(arg){\n        try { return obj.open(arg); } catch(_e){ return null; }\n      };\n      fn.__wrapped_from_object = true;\n      return fn;\n    }\n    // missing/unknown => no-op (never throw)\n    const noop = function(_arg){ return null; };\n    noop.__noop = true;\n    return noop;\n  }\n\n  try{\n    // Use defineProperty to normalize future assignments too (robust).\n    let _val = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;\n    Object.defineProperty(window, 'VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2', {\n      configurable: true,\n      enumerable: true,\n      get: function(){ return _val; },\n      set: function(v){ _val = normalize(v); }\n    });\n    // trigger normalization on current value\n    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = _val;\n  }catch(_e){\n    // fallback if defineProperty is blocked\n    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = normalize(window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2);\n  }\n})();\n\n/* P0_DRILLDOWN_LOCAL_V4 */\n  // P0: force local symbol to be FUNCTION (prevents "is not a function" even with shadowing)\n  try{\n    var __vsp_stub = function(){\n      try{ console.info("[VSP_DASH][P0] drilldown stub called"); }catch(_){}\n      return { open:function(){}, show:function(){}, close:function(){}, destroy:function(){} };\n    };\n\n    // local symbol (works even if calls are bare identifier)\n    if (typeof VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {\n      var VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = __vsp_stub; // var is function-scoped in IIFE\n      try{ console.info("[VSP_DASH][P0] drilldown local stub armed"); }catch(_){}\n    }\n\n    // window symbol too (for other modules)\n    if (typeof window !== "undefined" && typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {\n      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;\n      try{ console.info("[VSP_DASH][P0] drilldown window stub armed"); }catch(_){}\n    }\n  }catch(_){}\n\n  // P0 FIX (final2): ensure drilldown helper exists on window (function)\n  try{\n    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {\n      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){\n        try{ \nconsole.warn("[VSP_DASH] drilldown forced stub (window)");   // P0_DRILLDOWN_STUB: guarantee callable function\n  if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {\n    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){\n      try{ console.warn("[VSP_DASH][P0] drilldown stub used (no-op)"); }catch(_){}\n      return { open:function(){}, show:function(){}, destroy:function(){} };\n    };\n  }\n}catch(_){}\n        return false;\n      };\n    }\n  }catch(_){}\n// P0 FIX (final): drilldown dispatcher (avoid shadowed non-function symbols)\n  function __vsp_call_drilldown_artifacts(){\n    try{\n      const fn = (window && typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 === "function")\n        ? window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\n        : function(){ try{ console.warn("[VSP_DASH] drilldown skipped (no function on window)"); }catch(_){ } return false; };\n      return fn.apply(null, arguments);\n    }catch(_){\n      try{ console.warn("[VSP_DASH] drilldown dispatcher failed -> skipped"); }catch(__){}\n      return false;\n    }\n  }\n// P0 FIX (final): force drilldown helper onto window and call window.* to avoid shadowed const/object\n  try{\n    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {\n      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){\n        try{ console.warn("[VSP_DASH] drilldown forced stub (window)"); }catch(_){}\n        return false;\n      };\n    }\n  }catch(_){}\n// P0 FIX (hard): ALL drilldown helpers must never crash dashboard\n  function __vsp_stub_drill(name){\n    try{\n      const fn = function(){\n        try{ console.warn("[VSP_DASH] drilldown helper forced stub:", name); }catch(_){}\n        return false;\n      };\n      // local symbol if exists\n      try{\n        if (typeof eval(name) !== "function") { /* ignore */ }\n      }catch(_){}\n      // window symbol\n      try{\n        if (typeof window[name] !== "function") window[name] = fn;\n      }catch(_){}\n    }catch(_){}\n  }\n  try{\n    __vsp_stub_drill("VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2");\n    __vsp_stub_drill("VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2");\n  }catch(_){}\n// P0 FIX (hard): drilldown must never crash dashboard\n  try{\n    // local symbol (if exists / if not declared -> catch)\n    if (typeof VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {\n      VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){\n        try{ console.warn("[VSP_DASH] drilldown helper not a function -> forced stub"); }catch(_){}\n        return false;\n      };\n    }\n  }catch(_){}\n  try{\n    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {\n      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){\n        try{ console.warn("[VSP_DASH] drilldown helper missing -> forced stub"); }catch(_){}\n        return false;\n      };\n    }\n  }catch(_){}\n// P0 FIX: avoid ReferenceError if drilldown artifacts helper is missing\n  if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== 'function') {\n    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){\n      try{ console.warn("[VSP_DASH] drilldown helper missing -> skipped"); }catch(_){}\n      return false;\n    };\n  }\n// P0 FIX: avoid ReferenceError if drilldown artifacts helper is missing\n  if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== 'function') {\n    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){\n      try{ console.warn("[VSP_DASH] drilldown helper missing -> skipped"); }catch(_){}\n      return false;\n    };\n  }\n// === VSP_DASH_KPI_FROM_EXTRAS_P1_V4 ===\n  (function(){\n    if(window.__VSP_DASH_KPI_FROM_EXTRAS_P1_V4) return;\n    window.__VSP_DASH_KPI_FROM_EXTRAS_P1_V4 = 1;\n\n    function normRid(x){\n      try{\n        x = String(x || "").trim();\n        x = x.replace(/^RUN[_\-\s]+/i, "");\n        x = x.replace(/^RID[:\s]+/i, "");\n        const m = x.match(/(VSP_CI_\d{8}_\d{6})/i);\n        if(m && m[1]) return m[1];\n        return x.replace(/\s+/g, "_");\n      }catch(_){ return ""; }\n    }\n\n    function getRidBestEffort(){\n      // 1) global state (if any)\n      try{\n        const st = window.__VSP_RID_STATE__ || window.__VSP_RID_STATE || window.VSP_RID_STATE || window.__vsp_rid_state;\n        if(st){\n          if(st.rid || st.run_id) return normRid(st.rid || st.run_id);\n          if(st.state && (st.state.rid || st.state.run_id)) return normRid(st.state.rid || st.state.run_id);\n          if(typeof st.get === "function"){\n            const v = st.get();\n            if(v && (v.rid || v.run_id)) return normRid(v.rid || v.run_id);\n          }\n        }\n      }catch(_){}\n\n      // 2) header text contains "RID:"\n      try{\n        const body = document.body ? (document.body.innerText || "") : "";\n        const m = body.match(/RID:\s*(VSP_CI_\d{8}_\d{6})/i);\n        if(m && m[1]) return normRid(m[1]);\n      }catch(_){}\n\n      return "";\n    }\n\n    function setText(id, v){\n      const el = document.getElementById(id);\n      if(!el) return false;\n      el.textContent = (v===0) ? "0" : (v ? String(v) : "—");\n      return true;\n    }\n\n    function fmtBySev(bySev){\n      if(!bySev) return "";\n      const order = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];\n      const out = [];\n      for(const k of order){\n        if(bySev[k] !== undefined) out.push(k + ":" + bySev[k]);\n      }\n      return out.join(" ");\n    }\n\n    function pickTool(byTool, want){\n      if(!byTool) return null;\n      if(byTool[want] !== undefined) return byTool[want];\n      const key = Object.keys(byTool).find(k => String(k||"").toUpperCase() === want.toUpperCase());\n      return key ? byTool[key] : null;\n    }\n\n    function applyExtras(rid, kpi){\n      if(!kpi) return;\n      const total = kpi.total ?? 0;\n      const eff = kpi.effective ?? 0;\n      const degr = kpi.degraded ?? 0;\n      const unk = kpi.unknown_count ?? 0;\n      const score = (kpi.score === undefined || kpi.score === null) ? "" : kpi.score;\n\n      const status = (degr > 0) ? "DEGRADED" : (total > 0 ? "OK" : "EMPTY");\n\n      // commercial 4tabs KPI ids (exist in template)\n      setText("kpi-overall", score !== "" ? (score + "/100") : status);\n      setText("kpi-overall-sub", `total ${total} | eff ${eff} | degr ${degr} | unk ${unk}`);\n\n      setText("kpi-gate", status);\n      setText("kpi-gate-sub", fmtBySev(kpi.by_sev));\n\n      const gtl = pickTool(kpi.by_tool, "GITLEAKS");\n      setText("kpi-gitleaks", (gtl === null) ? "NOT_RUN" : gtl);\n      setText("kpi-gitleaks-sub", "GITLEAKS");\n\n      const cql = pickTool(kpi.by_tool, "CODEQL");\n      setText("kpi-codeql", (cql === null) ? "NOT_RUN" : cql);\n      setText("kpi-codeql-sub", "CODEQL");\n\n      // if dashboard_2025 ids exist, also fill\n      setText("kpi-total", total);\n      setText("kpi-effective", eff);\n      setText("kpi-degraded", degr);\n      setText("kpi-score", score);\n    }\n\n    function fetchExtras(rid){\n      const u = "/api/vsp/dashboard_v3_extras_v1?rid=" + encodeURIComponent(rid || "");\n      return fetch(u, {cache:"no-store"})\n        .then(r => r.ok ? r.json() : null)\n        .then(j => (j && j.ok && j.kpi) ? j.kpi : null)\n        .catch(_ => null);\n    }\n\n    let lastRid = "";\n    function hydrate(force){\n      const rid = getRidBestEffort();\n      if(!rid) return;\n      if(!force && rid === lastRid) return;\n      lastRid = rid;\n      fetchExtras(rid).then(kpi => { if(kpi) applyExtras(rid, kpi); });\n    }\n\n    // run on navigation + periodic\n    window.addEventListener("hashchange", () => setTimeout(() => hydrate(true), 120));\n    setTimeout(() => hydrate(true), 300);\n    setInterval(() => hydrate(false), 1500);\n    setInterval(() => hydrate(true), 15000);\n  })();\n  // === /VSP_DASH_KPI_FROM_EXTRAS_P1_V4 ===\n\n\n  // === VSP_DASHBOARD_KPI_WIRE_EXTRAS_P1_V2 ===\n  (function(){\n    if(window.__VSP_KPI_EXTRAS_WIRED_P1_V2) return;\n    window.__VSP_KPI_EXTRAS_WIRED_P1_V2 = 1;\n\n    function _ridFromState(){\n      try{\n        const candidates = [\n          window.__vsp_rid_state,\n          window.VSP_RID_STATE,\n          window.VSP_RID_STATE_V1,\n          window.__VSP_RID_STATE\n        ].filter(Boolean);\n\n        for(const st of candidates){\n          if(typeof st.get === "function"){\n            const r = st.get();\n            if(r && (r.rid || r.run_id)) return (r.rid || r.run_id);\n          }\n          if(st && (st.rid || st.run_id)) return (st.rid || st.run_id);\n          if(st && st.state && (st.state.rid || st.state.run_id)) return (st.state.rid || st.state.run_id);\n        }\n      }catch(_){}\n      return "";\n    }\n\n    function getRidBestEffort(){\n      const r0 = _ridFromState();\n      if(r0) return String(r0).trim();\n\n      // try DOM (some headers render RID: XXX)\n      try{\n        const body = document.body ? (document.body.innerText || "") : "";\n        const m = body.match(/RID:\s*(VSP_[A-Z0-9_]+)/);\n        if(m && m[1]) return m[1];\n      }catch(_){}\n      return "";\n    }\n\n    function setText(id, val){\n      const el = document.getElementById(id);\n      if(!el) return;\n      el.textContent = (val===undefined || val===null || val==="") ? "—" : String(val);\n    }\n\n    function setSub(id, val){\n      const el = document.getElementById(id);\n      if(!el) return;\n      el.textContent = (val===undefined || val===null) ? "" : String(val);\n    }\n\n    function fmtSev(bySev){\n      if(!bySev) return "";\n      const order = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];\n      const parts = [];\n      for(const k of order){\n        if(bySev[k]!==undefined && bySev[k]!==null) parts.push(k+":"+bySev[k]);\n      }\n      return parts.join(" ");\n    }\n\n    function pickTool(byTool, want){\n      if(!byTool) return null;\n      if(byTool[want]!==undefined) return byTool[want];\n      try{\n        const key = Object.keys(byTool).find(k => String(k||"").toUpperCase() === String(want).toUpperCase());\n        if(key) return byTool[key];\n      }catch(_){}\n      return null;\n    }\n\n    function applyExtras(rid, kpi){\n      if(!kpi) return;\n\n      const total = kpi.total || 0;\n      const eff = kpi.effective || 0;\n      const degr = kpi.degraded || 0;\n      const unk  = (kpi.unknown_count===undefined || kpi.unknown_count===null) ? "" : kpi.unknown_count;\n      const score = (kpi.score===undefined || kpi.score===null) ? "" : kpi.score;\n\n      const status = (degr>0) ? "DEGRADED" : (total>0 ? "OK" : "EMPTY");\n\n      // These KPI ids are used by vsp_4tabs_commercial_v1.html (commercial panel)\n      setText("kpi-overall", score!=="" ? (score + "/100") : status);\n      setSub ("kpi-overall-sub", "total " + total + " | eff " + eff + " | degr " + degr + (unk!=="" ? (" | unk "+unk) : ""));\n\n      setText("kpi-gate", status);\n      setSub ("kpi-gate-sub", fmtSev(kpi.by_sev));\n\n      const gtl = pickTool(kpi.by_tool, "GITLEAKS");\n      setText("kpi-gitleaks", (gtl===null || gtl===undefined) ? "NOT_RUN" : gtl);\n      setSub ("kpi-gitleaks-sub", (gtl===null || gtl===undefined) ? "tool=GITLEAKS missing" : ("tool=GITLEAKS | rid=" + rid));\n\n      const cql = pickTool(kpi.by_tool, "CODEQL");\n      setText("kpi-codeql", (cql===null || cql===undefined) ? "NOT_RUN" : cql);\n      setSub ("kpi-codeql-sub", (cql===null || cql===undefined) ? "tool=CODEQL missing" : ("tool=CODEQL | rid=" + rid));\n    }\n\n    function fetchExtras(rid){\n      const u = "/api/vsp/dashboard_v3_extras_v1?rid=" + encodeURIComponent(rid||"");\n      return fetch(u, {cache:"no-store"})\n        .then(r => r.ok ? r.json() : null)\n        .then(j => (j && j.ok && j.kpi) ? j.kpi : null)\n        .catch(_ => null);\n    }\n\n    let lastRid = "";\n    function tick(force){\n      const rid = getRidBestEffort();\n      if(!rid) return;\n      if(!force && rid === lastRid) return;\n      lastRid = rid;\n\n      fetchExtras(rid).then(kpi => {\n        if(kpi) applyExtras(rid, kpi);\n      });\n    }\n\n    window.addEventListener("hashchange", function(){ setTimeout(function(){ tick(true); }, 150); });\n    document.addEventListener("visibilitychange", function(){ if(!document.hidden) setTimeout(function(){ tick(true); }, 150); });\n\n    // first paint + periodic refresh\n    setTimeout(function(){ tick(true); }, 300);\n    setInterval(function(){ tick(false); }, 1500);\n    setInterval(function(){ tick(true); }, 15000);\n  })();\n\n\n  // === VSP_DASHBOARD_USE_EXTRAS_P1_V2 ===\n  function fetchDashboardExtras(rid){\n    const u = `/api/vsp/dashboard_v3_extras_v1?rid=${encodeURIComponent(rid||"")}`;\n    return fetch(u, {cache:"no-store"})\n      .then(r => r.ok ? r.json() : null)\n      .then(j => (j && j.ok && j.kpi) ? j.kpi : null)\n      .catch(_ => null);\n  }\n\n  function setTextSafe(id, val){\n    try{\n      const el = document.getElementById(id);\n      if(!el) return false;\n      el.textContent = (val===null || val===undefined) ? "N/A" : String(val);\n      return true;\n    }catch(_){ return false; }\n  }\n\n  function applyKpiExtrasToDom(kpi){\n    if(!kpi) return;\n    // try common ids (non-breaking if missing)\n    setTextSafe("kpi-total", kpi.total);\n    setTextSafe("kpi-score", kpi.score);\n    setTextSafe("kpi-effective", kpi.effective);\n    setTextSafe("kpi-degraded", kpi.degraded);\n\n    // also try a few other likely ids used in your UI patches\n    setTextSafe("kpi-total-findings", kpi.total);\n    setTextSafe("kpi-effective-findings", kpi.effective);\n    setTextSafe("kpi-degraded-findings", kpi.degraded);\n  }\n  // === /VSP_DASHBOARD_USE_EXTRAS_P1_V2 ===\n\n\n  // --- tiny utils ---\n  const LOG_ONCE = new Set();\n  function logOnce(k, ...a){ if(LOG_ONCE.has(k)) return; LOG_ONCE.add(k); console.log(...a); }\n  function nowMs(){ try { return Date.now(); } catch(_){ return 0; } }\n\n  function ridFromPage(){\n    // best-effort: try globals, DOM attrs, URL params\n    try {\n      if (window.VSP_RID) return String(window.VSP_RID);\n      if (window.__VSP_RID__) return String(window.__VSP_RID__);\n    } catch(_){}\n    try {\n      const u = new URL(location.href);\n      const rid = u.searchParams.get("rid") || u.searchParams.get("run_id") || u.searchParams.get("id");\n    fetchDashboardExtras(rid).then(applyKpiExtrasToDom);\n      if (rid) return String(rid);\n    } catch(_){}\n    try {\n      const el = document.querySelector("[data-rid],[data-run-id],[data-runid]");\n      const v = el && (el.getAttribute("data-rid") || el.getAttribute("data-run-id") || el.getAttribute("data-runid"));\n      if (v) return String(v);\n    } catch(_){}\n    return null;\n  }\n\n  function openTab(tabId){\n    // expects your 4-tabs router to exist; best-effort click\n    try {\n      // common patterns: button#tab-datasource / a[href='#datasource']\n      const btn = document.querySelector("#tab-" + tabId + ", [data-tab='"+tabId+"'], a[href='#"+tabId+"']");\n      if (btn) { btn.click(); return true; }\n    } catch(_){}\n    // fallback: try call existing router func if you have one\n    try {\n      if (typeof window.VSP_SWITCH_TAB === "function") { window.VSP_SWITCH_TAB(tabId); return true; }\n      if (typeof window.vspSwitchTab === "function") { window.vspSwitchTab(tabId); return true; }\n    } catch(_){}\n    return false;\n  }\n\n  // --- datasource filter bus (localStorage + CustomEvent) ---\n  const LS_KEY = "vsp_ds_filters_v1";\n\n  function pushDatasourceFilters(filters, opts){\n    opts = opts || {};\n    const payload = {\n      v: 1,\n      ts: nowMs(),\n      rid: opts.rid || ridFromPage(),\n      filters: filters || {}\n    };\n    try { localStorage.setItem(LS_KEY, JSON.stringify(payload)); } catch(_){}\n    try {\n      window.dispatchEvent(new CustomEvent("vsp:datasource:setFilters", { detail: payload }));\n    } catch(_){}\n  }\n\n  // public API for drilldown\n  window.VSP_DRILL_TO_DATASOURCE = function(filters, opts){\n    try {\n      pushDatasourceFilters(filters || {}, opts || {});\n      openTab("datasource");\n    } catch(e) {\n      console.warn("[VSP][DRILL] failed", e);\n    }\n  };\n\n  // --- export probe: make it quiet + stop after first success ---\n  async function probeExportOnce(url){\n    // HEAD is often blocked/noisy in browser setups; fallback to GET safely.\n    try {\n      const r = await fetch(url, { method: "HEAD", cache: "no-store", credentials: "same-origin" });\n      if (r && r.ok) return { ok:true, via:"HEAD", status:r.status, headers:r.headers };\n    } catch(_){}\n    try {\n      const r = await fetch(url + (url.includes("?") ? "&" : "?") + "_probe=1", { method: "GET", cache: "no-store", credentials: "same-origin" });\n      if (r && r.ok) return { ok:true, via:"GET", status:r.status, headers:r.headers };\n      return { ok:false, via:"GET", status: (r && r.status) || 0, headers: r && r.headers };\n    } catch(e){\n      return { ok:false, via:"ERR", status:0, err:String(e) };\n    }\n  }\n\n  async function commercialExportProbeQuiet(){\n    // only run on pages that show export controls\n    const rid = ridFromPage();\n    if (!rid) return;\n\n    // build canonical export URL once (commercial behavior)\n    const base = (window.VSP_RUN_EXPORT_BASE || "/api/vsp/run_export_v3").replace(/\/+$/,"");\n    const pdfUrl = base + "/" + encodeURIComponent(rid) + "?fmt=pdf";\n\n    const key = "export-probe-" + rid;\n    if (window.__VSP_EXPORT_PROBED__ && window.__VSP_EXPORT_PROBED__[rid]) return;\n    window.__VSP_EXPORT_PROBED__ = window.__VSP_EXPORT_PROBED__ || {};\n    window.__VSP_EXPORT_PROBED__[rid] = true;\n\n    const res = await probeExportOnce(pdfUrl);\n    // treat failures as non-fatal; do NOT spam console\n    if (!res.ok){\n      logOnce(key+"-fail", "[VSP][EXPORT][PROBE] pdf probe not OK (non-fatal)", { rid, url: pdfUrl, via: res.via, status: res.status });\n      window.VSP_EXPORT_AVAILABLE = window.VSP_EXPORT_AVAILABLE || {};\n      window.VSP_EXPORT_AVAILABLE.pdf = 0;\n      return;\n    }\n\n    // success: set availability and stop further probes\n    window.VSP_EXPORT_AVAILABLE = window.VSP_EXPORT_AVAILABLE || {};\n    window.VSP_EXPORT_AVAILABLE.pdf = 1;\n    logOnce(key+"-ok", "[VSP][EXPORT][PROBE] pdf available", { rid, via: res.via, status: res.status });\n\n    // if you have UI pills/badges, update them quietly\n    try {\n      const pill = document.querySelector("[data-export='pdf'], #pill-export-pdf, #pill-pdf");\n      if (pill) { pill.classList.add("is-ok"); pill.classList.remove("is-bad"); }\n    } catch(_){}\n  }\n\n  // run once after DOM ready\n  function onReady(fn){\n    if (document.readyState === "complete" || document.readyState === "interactive") return setTimeout(fn, 0);\n    document.addEventListener("DOMContentLoaded", fn, { once: true });\n  }\n\n  // --- attach drilldown click helpers (best-effort, non-breaking) ---\n  function wireDrilldownClicks(){\n    // opt-in attributes (recommended): data-vsp-drill-tool / data-vsp-drill-sev / data-vsp-drill-cwe\n    const els = document.querySelectorAll("[data-vsp-drill-tool],[data-vsp-drill-sev],[data-vsp-drill-cwe]");\n    els.forEach(el=>{\n      if (el.__vsp_drilled__) return;\n      el.__vsp_drilled__ = true;\n      el.style.cursor = "pointer";\n      el.addEventListener("click", ()=>{\n        const tool = el.getAttribute("data-vsp-drill-tool");\n        const sev  = el.getAttribute("data-vsp-drill-sev");\n        const cwe  = el.getAttribute("data-vsp-drill-cwe");\n        const filters = {};\n        if (tool) filters.tool = tool;\n        if (sev)  filters.severity = sev;\n        if (cwe)  filters.cwe = cwe;\n        window.VSP_DRILL_TO_DATASOURCE(filters);\n      });\n    });\n\n    // fallback: gate summary pills often include tool/sev text\n    const pills = document.querySelectorAll(".vsp-pill,[data-pill]");\n    pills.forEach(p=>{\n      if (p.__vsp_drilled__) return;\n      const t = (p.textContent || "").trim();\n      // simple patterns: "GITLEAKS", "SEMGREP", "CRITICAL", "HIGH", "CWE-79"\n      // (intentionally empty; handled by wireFallbackPills)\n    });\n  }\n\n  // NOTE: avoid python-style in JS; keep safe fallback only\n  function wireFallbackPills(){\n    const pills = document.querySelectorAll(".vsp-pill,[data-pill]");\n    pills.forEach(p=>{\n      if (p.__vsp_drilled__) return;\n      const txt = (p.textContent || "").trim();\n      if (!txt) return;\n\n      const up = txt.toUpperCase();\n      const filters = {};\n      const toolSet = new Set(["GITLEAKS","SEMGREP","TRIVY","CODEQL","KICS","GRYPE","SYFT","BANDIT"]);\n      const sevSet  = new Set(["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]);\n      if (toolSet.has(up)) filters.tool = up;\n      if (sevSet.has(up))  filters.severity = up;\n      if (/^CWE-\d+$/i.test(up)) filters.cwe = up;\n\n      if (Object.keys(filters).length === 0) return;\n\n      p.__vsp_drilled__ = true;\n      p.style.cursor = "pointer";\n      p.title = "Click to drilldown → Data Source";\n      p.addEventListener("click", ()=> window.VSP_DRILL_TO_DATASOURCE(filters));\n    });\n  }\n\n  onReady(()=>{\n    try { commercialExportProbeQuiet(); } catch(e){ /* silent */ }\n    try { wireDrilldownClicks(); } catch(e){ /* silent */ }\n    try { wireFallbackPills(); } catch(e){ /* silent */ }\n  });\n\n})();\n\n\n/* VSP_DASH_BADGES_P1_V1: Dashboard badges for Degraded tools + Rule Overrides delta (live RID) */\n(function(){\n  'use strict';\n\n  async function _j(url, timeoutMs=6000){\n    const ctrl = new AbortController();\n    const t = setTimeout(()=>ctrl.abort(), timeoutMs);\n    try{\n      const r = await fetch(url, {signal: ctrl.signal, headers:{'Accept':'application/json'}});\n      const ct = (r.headers.get('content-type')||'').toLowerCase();\n      if(!ct.includes('application/json')) return null;\n      return await r.json();\n    }catch(e){\n      return null;\n    }finally{\n      clearTimeout(t);\n    }\n  }\n\n  function _getRidFromLocal(){\n    const keys = ["vsp_selected_rid_v2","vsp_selected_rid","vsp_current_rid","VSP_RID","vsp_rid"];\n    for(const k of keys){\n      try{\n        const v = localStorage.getItem(k);\n        if(v && v !== "null" && v !== "undefined") return v;\n      }catch(e){}\n    }\n    return null;\n  }\n\n  async function _getRid(){\n    try{\n      if(window.VSP_RID && typeof window.VSP_RID.get === "function"){\n        const r = window.VSP_RID.get();\n        if(r) return r;\n      }\n    }catch(e){}\n    const l = _getRidFromLocal();\n    if(l) return l;\n\n    const x = await _j("/api/vsp/latest_rid_v1");\n    if(x && x.ok && x.run_id) return x.run_id;\n    return null;\n  }\n\n  function _findDashHost(){\n    return document.getElementById("vsp4-dashboard")\n      || document.querySelector("[data-tab='dashboard']")\n      || document.querySelector("#tab-dashboard")\n      || document.querySelector(".vsp-dashboard")\n      || document.querySelector("main")\n      || document.body;\n  }\n\n  function _ensureBar(){\n    const host = _findDashHost();\n    if(!host) return null;\n\n    let bar = document.getElementById("vsp-dash-p1-badges");\n    if(bar) return bar;\n\n    bar = document.createElement("div");\n    bar.id = "vsp-dash-p1-badges";\n    bar.style.cssText = "margin:10px 0 12px 0;padding:10px 12px;border:1px solid rgba(148,163,184,.18);border-radius:14px;background:rgba(2,6,23,.35);display:flex;gap:10px;flex-wrap:wrap;align-items:center;";\n\n    function pill(id, label){\n      const a = document.createElement("a");\n      a.href="#";\n      a.id=id;\n      a.style.cssText = "display:inline-flex;gap:8px;align-items:center;padding:7px 10px;border-radius:999px;border:1px solid rgba(148,163,184,.22);text-decoration:none;color:#cbd5e1;font-size:12px;white-space:nowrap;";\n      a.innerHTML = `<b style="font-weight:700;color:#e2e8f0">${label}</b><span style="opacity:.9" data-val>loading…</span>`;\n      return a;\n    }\n\n    bar.appendChild(pill("vsp-pill-degraded","Degraded"));\n    bar.appendChild(pill("vsp-pill-overrides","Overrides"));\n    bar.appendChild(pill("vsp-pill-rid","RID"));\n\n    host.prepend(bar);\n    return bar;\n  }\n\n  function _setPill(id, text){\n    const a = document.getElementById(id);\n    if(!a) return;\n    const v = a.querySelector("[data-val]");\n    if(v) v.textContent = text;\n  }\n\n  function _fmtDegraded(st){\n    const arr = (st && st.degraded_tools) ? st.degraded_tools : [];\n    if(!arr || !arr.length) return "none";\n    const parts = [];\n    for(const it of arr.slice(0,4)){\n      const tool = it.tool || it.name || "tool";\n      const rc = (it.rc !== undefined && it.rc !== null) ? `rc=${it.rc}` : "";\n      const v  = it.verdict ? String(it.verdict) : "";\n      const why = it.reason || it.error || it.note || "";\n      const one = [tool, v, rc].filter(Boolean).join(":") + (why ? ` (${String(why).slice(0,30)})` : "");\n      parts.push(one.trim());\n    }\n    return parts.join(" | ") + (arr.length>4 ? ` (+${arr.length-4})` : "");\n  }\n\n  function _fmtOverrides(eff){\n    const d = (eff && eff.delta) ? eff.delta : {};\n    const matched = d.matched_n ?? 0;\n    const applied = d.applied_n ?? 0;\n    const sup = d.suppressed_n ?? 0;\n    const chg = d.changed_severity_n ?? 0;\n    const exp = d.expired_match_n ?? 0;\n    return `matched=${matched} applied=${applied} suppressed=${sup} changed=${chg} expired=${exp}`;\n  }\n\n  async function refresh(){\n    _ensureBar();\n    const rid = await _getRid();\n    _setPill("vsp-pill-rid", rid || "n/a");\n    if(!rid) return;\n\n    const [st, eff] = await Promise.all([\n      _j(`/api/vsp/run_status_v2/${encodeURIComponent(rid)}`),\n      _j(`/api/vsp/findings_effective_v1/${encodeURIComponent(rid)}?limit=0`)\n    ]);\n\n    _setPill("vsp-pill-degraded", _fmtDegraded(st));\n    _setPill("vsp-pill-overrides", _fmtOverrides(eff));\n  }\n\n  document.addEventListener("click", function(ev){\n    const a = ev.target && ev.target.closest && ev.target.closest("#vsp-pill-degraded,#vsp-pill-overrides");\n    if(!a) return;\n    ev.preventDefault();\n    try{\n      if(window.VSP_DASH_DRILLDOWN && typeof window.VSP_DASH_DRILLDOWN.open === "function"){\n        window.VSP_DASH_DRILLDOWN.open();\n      }\n    }catch(e){}\n  }, true);\n\n  window.addEventListener("vsp:rid_changed", function(){ refresh(); });\n  window.addEventListener("hashchange", function(){ setTimeout(refresh, 120); });\n  window.addEventListener("load", function(){ setTimeout(refresh, 200); });\n\n  setTimeout(refresh, 250);\n})();\n\n\n/* VSP_DASH_BADGES_P1_V3_FIXEDBAR: ensure badges visible even if dashboard host selector mismatch */\n(function(){\n  'use strict';\n\n  function _pickHost(){\n    // 1) container that holds KPI cards\n    const card = document.querySelector(".vsp-card, .dashboard-card, .card");\n    if(card && card.parentElement) return card.parentElement;\n\n    // 2) active tab pane (common patterns)\n    const active = document.querySelector(".tab-pane.active, .tab-content .active, [role='tabpanel'][aria-hidden='false']");\n    if(active) return active;\n\n    // 3) main content region\n    return document.querySelector("main") || document.body;\n  }\n\n  function _ensureFixedStyle(){\n    if(document.getElementById("vsp-dash-fixed-style")) return;\n    const st = document.createElement("style");\n    st.id="vsp-dash-fixed-style";\n    st.textContent = `\n      #vsp-dash-p1-badges{ z-index:9999; }\n      #vsp-dash-p1-badges.vsp-fixed{\n        position: sticky;\n        top: 0;\n        backdrop-filter: blur(8px);\n        background: rgba(2,6,23,.60) !important;\n      }\n    `;\n    document.head.appendChild(st);\n  }\n\n  // override ensureBar from V1 (if exists) by recreating bar + sticky class\n  function ensureBarV3(){\n    _ensureFixedStyle();\n    let bar = document.getElementById("vsp-dash-p1-badges");\n    if(bar) {\n      bar.classList.add("vsp-fixed");\n      return bar;\n    }\n    const host = _pickHost();\n    if(!host) return null;\n\n    bar = document.createElement("div");\n    bar.id = "vsp-dash-p1-badges";\n    bar.className = "vsp-fixed";\n    bar.style.cssText = "margin:0 0 12px 0;padding:10px 12px;border:1px solid rgba(148,163,184,.18);border-radius:14px;background:rgba(2,6,23,.35);display:flex;gap:10px;flex-wrap:wrap;align-items:center;";\n\n    function pill(id, label){\n      const a = document.createElement("a");\n      a.href="#";\n      a.id=id;\n      a.style.cssText = "display:inline-flex;gap:8px;align-items:center;padding:7px 10px;border-radius:999px;border:1px solid rgba(148,163,184,.22);text-decoration:none;color:#cbd5e1;font-size:12px;white-space:nowrap;";\n      a.innerHTML = `<b style="font-weight:700;color:#e2e8f0">${label}</b><span style="opacity:.9" data-val>loading…</span>`;\n      return a;\n    }\n\n    bar.appendChild(pill("vsp-pill-degraded","Degraded"));\n    bar.appendChild(pill("vsp-pill-overrides","Overrides"));\n    bar.appendChild(pill("vsp-pill-rid","RID"));\n\n    host.prepend(bar);\n    return bar;\n  }\n\n  // kick once after load to guarantee visibility\n  window.addEventListener("load", function(){\n    setTimeout(()=>{ try{ ensureBarV3(); }catch(e){} }, 200);\n  });\n  window.addEventListener("hashchange", function(){\n    setTimeout(()=>{ try{ ensureBarV3(); }catch(e){} }, 120);\n  });\n  window.addEventListener("vsp:rid_changed", function(){\n    setTimeout(()=>{ try{ ensureBarV3(); }catch(e){} }, 50);\n  });\n})();\n\n\n/* VSP_DASH_DRILLDOWN_P1_V1: openable drilldown panel for Degraded + Overrides */\n(function(){\n  'use strict';\n\n  async function _j(url, timeoutMs=8000){\n    const ctrl = new AbortController();\n    const t = setTimeout(()=>ctrl.abort(), timeoutMs);\n    try{\n      const r = await fetch(url, {signal: ctrl.signal, headers:{'Accept':'application/json'}});\n      const ct = (r.headers.get('content-type')||'').toLowerCase();\n      if(!ct.includes('application/json')) return null;\n      return await r.json();\n    }catch(e){\n      return null;\n    }finally{\n      clearTimeout(t);\n    }\n  }\n\n  function _getRidFromLocal(){\n    const keys = ["vsp_selected_rid_v2","vsp_selected_rid","vsp_current_rid","VSP_RID","vsp_rid"];\n    for(const k of keys){\n      try{\n        const v = localStorage.getItem(k);\n        if(v && v !== "null" && v !== "undefined") return v;\n      }catch(e){}\n    }\n    return null;\n  }\n\n  async function _getRid(){\n    try{\n      if(window.VSP_RID && typeof window.VSP_RID.get === "function"){\n        const r = window.VSP_RID.get();\n        if(r) return r;\n      }\n    }catch(e){}\n    const l = _getRidFromLocal();\n    if(l) return l;\n    const x = await _j("/api/vsp/latest_rid_v1");\n    if(x && x.ok && x.run_id) return x.run_id;\n    return null;\n  }\n\n  function _ensureUI(){\n    if(document.getElementById("vsp-dd-overlay")) return;\n\n    const st = document.createElement("style");\n    st.id = "vsp-dd-style";\n    st.textContent = `\n      #vsp-dd-overlay{position:fixed;inset:0;z-index:10000;background:rgba(0,0,0,.55);display:none;}\n      #vsp-dd-panel{position:fixed;top:60px;right:18px;bottom:18px;width:min(820px,calc(100vw - 36px));\n        z-index:10001;background:rgba(2,6,23,.96);border:1px solid rgba(148,163,184,.18);border-radius:18px;\n        box-shadow:0 20px 80px rgba(0,0,0,.55);display:none;overflow:hidden;}\n      #vsp-dd-head{display:flex;align-items:center;justify-content:space-between;padding:14px 14px;border-bottom:1px solid rgba(148,163,184,.14);}\n      #vsp-dd-title{font-weight:800;color:#e2e8f0;font-size:14px;letter-spacing:.2px}\n      #vsp-dd-actions{display:flex;gap:8px;flex-wrap:wrap;align-items:center}\n      .vsp-dd-btn{padding:7px 10px;border-radius:12px;border:1px solid rgba(148,163,184,.22);background:rgba(15,23,42,.55);\n        color:#cbd5e1;font-size:12px;cursor:pointer}\n      .vsp-dd-btn:hover{filter:brightness(1.08)}\n      #vsp-dd-body{padding:14px;overflow:auto;height:calc(100% - 56px);color:#cbd5e1}\n      .vsp-dd-card{border:1px solid rgba(148,163,184,.14);border-radius:16px;background:rgba(15,23,42,.35);padding:12px 12px;margin-bottom:12px;}\n      .vsp-dd-kv{display:grid;grid-template-columns:160px 1fr;gap:6px 12px;font-size:12px;}\n      .vsp-dd-k{opacity:.85}\n      .vsp-dd-v{color:#e2e8f0}\n      .vsp-dd-table{width:100%;border-collapse:separate;border-spacing:0 8px;font-size:12px;}\n      .vsp-dd-table td{padding:8px 10px;border:1px solid rgba(148,163,184,.14);background:rgba(2,6,23,.35);}\n      .vsp-dd-table tr td:first-child{border-radius:12px 0 0 12px;}\n      .vsp-dd-table tr td:last-child{border-radius:0 12px 12px 0;}\n      .vsp-dd-muted{opacity:.75}\n      .vsp-dd-link{color:#93c5fd;text-decoration:none}\n      .vsp-dd-link:hover{text-decoration:underline}\n      code.vsp-dd-code{background:rgba(2,6,23,.6);border:1px solid rgba(148,163,184,.16);padding:2px 6px;border-radius:8px}\n    `;\n    document.head.appendChild(st);\n\n    const ov = document.createElement("div");\n    ov.id="vsp-dd-overlay";\n    ov.addEventListener("click", close);\n    document.body.appendChild(ov);\n\n    const panel = document.createElement("div");\n    panel.id="vsp-dd-panel";\n    panel.innerHTML = `\n      <div id="vsp-dd-head">\n        <div id="vsp-dd-title">Drilldown</div>\n        <div id="vsp-dd-actions">\n          <button class="vsp-dd-btn" id="vsp-dd-refresh">Refresh</button>\n          <button class="vsp-dd-btn" id="vsp-dd-copy">Copy RID</button>\n          <button class="vsp-dd-btn" id="vsp-dd-close">Close</button>\n        </div>\n      </div>\n      <div id="vsp-dd-body">\n        <div class="vsp-dd-card"><div class="vsp-dd-muted">Loading…</div></div>\n      </div>\n    `;\n    document.body.appendChild(panel);\n\n    document.getElementById("vsp-dd-close").addEventListener("click", close);\n    document.getElementById("vsp-dd-refresh").addEventListener("click", render);\n    document.getElementById("vsp-dd-copy").addEventListener("click", async ()=>{\n      const rid = await _getRid();\n      try{ await navigator.clipboard.writeText(rid||""); }catch(e){}\n    });\n\n    window.addEventListener("keydown", (e)=>{\n      if(e.key === "Escape") close();\n    });\n  }\n\n  function open(){\n    _ensureUI();\n    document.getElementById("vsp-dd-overlay").style.display="block";\n    document.getElementById("vsp-dd-panel").style.display="block";\n    render();\n  }\n\n  function close(){\n    const ov=document.getElementById("vsp-dd-overlay");\n    const pn=document.getElementById("vsp-dd-panel");\n    if(ov) ov.style.display="none";\n    if(pn) pn.style.display="none";\n  }\n\n  function _fmtOverrides(eff){\n    const d = (eff && eff.delta) ? eff.delta : {};\n    const matched = d.matched_n ?? 0;\n    const applied = d.applied_n ?? 0;\n    const sup = d.suppressed_n ?? 0;\n    const chg = d.changed_severity_n ?? 0;\n    const exp = d.expired_match_n ?? 0;\n    return {matched, applied, sup, chg, exp, now_utc: d.now_utc || ""};\n  }\n\n  function _htmlEscape(x){\n    return String(x||"").replace(/[&<>"]/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;" }[c]));
  }

  async function render(){
    _ensureUI();
    const body = document.getElementById("vsp-dd-body");
    const title = document.getElementById("vsp-dd-title");
    const rid = await _getRid();
    title.textContent = rid ? `Drilldown • ${rid}` : "Drilldown • (no RID)";

    if(!rid){
      body.innerHTML = `<div class="vsp-dd-card"><div class="vsp-dd-muted">No RID selected.</div></div>`;
      return;
    }

    body.innerHTML = `<div class="vsp-dd-card"><div class="vsp-dd-muted">Loading ${_htmlEscape(rid)}…</div></div>`;

    const [st, eff, art] = await Promise.all([
      _j(`/api/vsp/run_status_v2/${encodeURIComponent(rid)}`),
      _j(`/api/vsp/findings_effective_v1/${encodeURIComponent(rid)}?limit=0`),
      _j(`/api/vsp/run_artifacts_index_v1/${encodeURIComponent(rid)}`)
    ]);

    const degraded = (st && st.degraded_tools) ? st.degraded_tools : [];
    const ov = _fmtOverrides(eff);

    let artHtml = `<div class="vsp-dd-muted">Artifacts: n/a</div>`;
    if(art && (art.ok || art.items)){
      const items = art.items || [];
      const links = items.slice(0,10).map(it=>{
        const name = _htmlEscape(it.name || it.file || "artifact");
        const url  = it.url || it.href || it.download_url || "";
        if(url) return `<a class="vsp-dd-link" href="${_htmlEscape(url)}" target="_blank" rel="noopener">${name}</a>`;
        return `<span class="vsp-dd-muted">${name}</span>`;
      });
      artHtml = `<div class="vsp-dd-muted">Artifacts:</div><div style="display:flex;gap:10px;flex-wrap:wrap;margin-top:6px;">${links.join(" ") || '<span class="vsp-dd-muted">empty</span>'}</div>`;
    }

    const degradedRows = (degraded||[]).map(it=>{
      const tool=_htmlEscape(it.tool || it.name || "");
      const verdict=_htmlEscape(it.verdict || "");
      const rc=(it.rc!==undefined && it.rc!==null) ? _htmlEscape(it.rc) : "";
      const reason=_htmlEscape(it.reason || it.error || it.note || "");
      return `<tr>
        <td><b>${tool}</b></td>
        <td>${verdict || '<span class="vsp-dd-muted">—</span>'}</td>
        <td>${rc || '<span class="vsp-dd-muted">—</span>'}</td>
        <td>${reason || '<span class="vsp-dd-muted">—</span>'}</td>
      </tr>`;
    }).join("");

    body.innerHTML = `
      <div class="vsp-dd-card">
        <div style="font-weight:800;color:#e2e8f0;margin-bottom:8px;">Overview</div>
        <div class="vsp-dd-kv">
          <div class="vsp-dd-k">RID</div><div class="vsp-dd-v"><code class="vsp-dd-code">${_htmlEscape(rid)}</code></div>
          <div class="vsp-dd-k">Overrides delta</div><div class="vsp-dd-v">matched=${ov.matched} • applied=${ov.applied} • suppressed=${ov.sup} • changed=${ov.chg} • expired=${ov.exp}</div>
          <div class="vsp-dd-k">Delta time</div><div class="vsp-dd-v">${_htmlEscape(ov.now_utc) || '<span class="vsp-dd-muted">—</span>'}</div>
          <div class="vsp-dd-k">Degraded tools</div><div class="vsp-dd-v">${(degraded||[]).length || 0}</div>
        </div>
        <div style="margin-top:10px;">${artHtml}</div>
      </div>

      <div class="vsp-dd-card">
        <div style="font-weight:800;color:#e2e8f0;margin-bottom:8px;">Degraded details</div>
        ${(degraded && degraded.length) ? `
          <table class="vsp-dd-table">
            <tr>
              <td><b>Tool</b></td><td><b>Verdict</b></td><td><b>RC</b></td><td><b>Reason</b></td>
            </tr>
            ${degradedRows}
          </table>
        ` : `<div class="vsp-dd-muted">No degraded tools.</div>`}
      </div>
    `;
  }

  window.VSP_DASH_DRILLDOWN = { open, close, render };
})();

VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2

/* VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2: pin important artifacts + quick-open buttons */
(function(){
  'use strict';
  if(!window.VSP_DASH_DRILLDOWN || typeof window.VSP_DASH_DRILLDOWN.render !== "function"){
    console.warn("\n/* DRILL_ART_V2_REPLACED_P0_V1 (commercial safe) */\n(function(){\n  'use strict';\n\n  // single public entrypoint\n  if (typeof window.VSP_DRILLDOWN !== 'function') {\n    window.VSP_DRILLDOWN = function(intent){\n      try{\n        // minimal safe behavior: go Data Source tab and store intent\n        try{ localStorage.setItem("vsp_last_drilldown_intent_v1", JSON.stringify(intent||{})); }catch(_){}\n        if (location && typeof location.hash === 'string') {\n          // prefer datasource (table) for all drilldowns\n          if (!location.hash.includes("datasource")) location.hash = "#datasource";\n        }\n        return true;\n      }catch(e){ return false; }\n    };\n  }\n\n  // hard legacy API (must be function)\n  function dd(intent){ return window.VSP_DRILLDOWN(intent); }\n  try{\n    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = dd;\n    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V1 = dd;\n    window.VSP_DASH_DRILLDOWN_ARTIFACTS = dd;\n  }catch(_){}\n\n  // optional: silence noisy install logs\n  try{ if(!window.__VSP_DD_ACCEPTED_ONCE){ window.__VSP_DD_ACCEPTED_ONCE=1; } }catch(_){}\n})();\n\n\n/* VSP_DASH_OPEN_REPORT_BTN_V1: open CIO report for live RID */\n(function(){\n  'use strict';\n  function normRid(x){\n    if(!x) return "";\n    return String(x).trim().replace(/^RID:\s*/i,'').replace(/^RUN_/i,'');\n  }\n  function getRid(){\n    try{\n      return normRid(localStorage.getItem("vsp_rid_selected_v2") || localStorage.getItem("vsp_rid_selected") || "");\n    }catch(e){ return ""; }\n  }\n\n  function inject(){\n    // try to attach near badges bar if exists; else top of body\n    const host = document.getElementById("vsp-dash-p1-badges") || document.body;\n    if(!host) return;\n\n    if(document.getElementById("vsp-open-cio-report-btn")) return;\n\n    const btn = document.createElement("button");\n    btn.id = "vsp-open-cio-report-btn";\n    btn.textContent = "Open CIO Report";\n    btn.style.cssText = "margin-left:10px; padding:8px 10px; border-radius:10px; font-size:12px; border:1px solid rgba(148,163,184,.35); background:rgba(2,6,23,.55); color:#e2e8f0; cursor:pointer;";\n    btn.addEventListener("click", function(){\n      const rid = getRid();\n      if(!rid){ alert("No RID selected"); return; }\n      window.open("/vsp/report_cio_v1/" + encodeURIComponent(rid), "_blank", "noopener");\n    });\n\n    // put into badges bar if possible\n    if(host && host.id === "vsp-dash-p1-badges"){\n      host.appendChild(btn);\n    }else{\n      document.body.insertBefore(btn, document.body.firstChild);\n    }\n  }\n\n  if(document.readyState === "loading") document.addEventListener("DOMContentLoaded", inject);\n  else inject();\n})();\n\nVSP_DASH_KPI_EFFECTIVE_DEGRADED_P1_V4\n\n/* VSP_DASH_KPI_EFFECTIVE_DEGRADED_P1_V4: show effective/raw + overrides delta + degraded clickable logs */\n(function(){\n  'use strict';\n\n  function normRid(x){\n    if(!x) return "";\n    return String(x).trim().replace(/^RID:\s*/i,'').replace(/^RUN_/i,'');\n  }\n  function getRid(){\n    try{\n      return normRid(localStorage.getItem("vsp_rid_selected_v2") || localStorage.getItem("vsp_rid_selected") || "");\n    }catch(e){ return ""; }\n  }\n  async function jget(url){\n    const r = await fetch(url, {cache:"no-store"});\n    const ct = (r.headers.get("content-type")||"");\n    if(!r.ok) throw new Error("HTTP "+r.status+" "+url);\n    if(ct.includes("application/json")) return await r.json();\n    // tolerate non-json\n    return {ok:false, _nonjson:true, text: await r.text()};\n  }\n  function ensureBar(){\n    let bar = document.getElementById("vsp-dash-p1-badges");\n    if(!bar){\n      bar = document.createElement("div");\n      bar.id="vsp-dash-p1-badges";\n      bar.style.cssText="position:sticky;top:0;z-index:9999;margin:10px 0;padding:10px;border-radius:14px;border:1px solid rgba(148,163,184,.18);background:rgba(2,6,23,.45);backdrop-filter: blur(6px);display:flex;flex-wrap:wrap;gap:10px;align-items:center;";\n      document.body.insertBefore(bar, document.body.firstChild);\n    }\n    return bar;\n  }\n  function pill(txt, tone){\n    const map = {\n      ok: "border:1px solid rgba(34,197,94,.35);",\n      warn:"border:1px solid rgba(245,158,11,.35);",\n      bad: "border:1px solid rgba(239,68,68,.35);",\n      info:"border:1px solid rgba(148,163,184,.25);"\n    };\n    return `<span style="display:inline-flex;align-items:center;gap:6px;padding:6px 10px;border-radius:999px;background:rgba(2,6,23,.35);color:#e2e8f0;font-size:12px;${map[tone]||map.info}">${txt}</span>`;\n  }\n  function linkPill(label, url, tone){\n    const map = {\n      ok: "border:1px solid rgba(34,197,94,.35);",\n      warn:"border:1px solid rgba(245,158,11,.35);",\n      bad: "border:1px solid rgba(239,68,68,.35);",\n      info:"border:1px solid rgba(148,163,184,.25);"\n    };\n    return `<a target="_blank" rel="noopener" href="${url}"\n      style="display:inline-flex;align-items:center;gap:6px;padding:6px 10px;border-radius:999px;background:rgba(2,6,23,.35);color:#e2e8f0;font-size:12px;text-decoration:none;${map[tone]||map.info}">\n      ${label}</a>`;\n  }\n\n  function pickLogRel(tool){\n    const t = String(tool||"").toLowerCase();\n    if(t.includes("kics")) return "kics/kics.log";\n    if(t.includes("trivy")) return "trivy/trivy.json.err";\n    if(t.includes("codeql")) return "codeql/codeql.log";\n    if(t.includes("semgrep")) return "semgrep/semgrep.json";\n    if(t.includes("gitleaks")) return "gitleaks/gitleaks.json";\n    if(t.includes("bandit")) return "bandit/bandit.json";\n    if(t.includes("syft")) return "syft/syft.json";\n    if(t.includes("grype")) return "grype/grype.json";\n    return "";\n  }\n  function artUrl(rid, rel){\n    return "/api/vsp/run_artifact_raw_v1/" + encodeURIComponent(rid) + "?rel=" + encodeURIComponent(rel);\n  }\n\n  async function render(){\n    const bar = ensureBar();\n    const rid = getRid() || (await jget("/api/vsp/latest_rid_v1")).run_id;\n    const ridN = normRid(rid||"");\n    if(!ridN){\n      bar.innerHTML = pill("RID: (none)", "warn") + pill("No RID selected", "warn");\n      return;\n    }\n\n    let eff=null, st=null;\n    try{\n      eff = await jget("/api/vsp/findings_effective_v1/" + encodeURIComponent(ridN) + "?limit=0");\n    }catch(e){\n      eff = {ok:false, error:String(e)};\n    }\n    try{\n      st = await jget("/api/vsp/run_status_v2/" + encodeURIComponent(ridN));\n    }catch(e){\n      st = {ok:false, error:String(e)};\n    }\n\n    const rawTotal = eff && typeof eff.raw_total==="number" ? eff.raw_total : null;\n    const effTotal = eff && typeof eff.effective_total==="number" ? eff.effective_total : null;\n    const d = (eff && eff.delta) ? eff.delta : {};\n    const sup = (d && typeof d.suppressed_n==="number") ? d.suppressed_n : null;\n    const chg = (d && typeof d.changed_severity_n==="number") ? d.changed_severity_n : null;\n    const match = (d && typeof d.matched_n==="number") ? d.matched_n : null;\n    const applied = (d && typeof d.applied_n==="number") ? d.applied_n : null;\n\n    const degraded = (st && st.degraded_tools && Array.isArray(st.degraded_tools)) ? st.degraded_tools : [];\n    const degrN = degraded.length;\n\n    let html = "";\n    html += pill("RID: "+ridN, "info");\n    if(rawTotal!=null && effTotal!=null){\n      const tone = (effTotal < rawTotal) ? "ok" : "info";\n      html += pill(`Effective ${effTotal} / Raw ${rawTotal}`, tone);\n    }else{\n      html += pill("Effective/Raw: n/a", "warn");\n    }\n\n    if(match!=null) html += pill(`Overrides matched: ${match}`, "info");\n    if(applied!=null) html += pill(`Overrides applied: ${applied}`, applied>0 ? "ok" : "info");\n    if(sup!=null) html += pill(`Suppressed: ${sup}`, sup>0 ? "ok" : "info");\n    if(chg!=null) html += pill(`Severity changed: ${chg}`, chg>0 ? "ok" : "info");\n\n    // degraded clickable\n    if(degrN>0){\n      html += pill(`Degraded tools: ${degrN}`, "warn");\n      degraded.slice(0,8).forEach(t=>{\n        const rel = pickLogRel(t);\n        if(rel) html += linkPill(`${t} log`, artUrl(ridN, rel), "warn");\n        else html += pill(String(t), "warn");\n      });\n    }else{\n      html += pill("Degraded: 0", "ok");\n    }\n\n    // quick links\n    html += linkPill("CIO Report", "/vsp/report_cio_v1/"+encodeURIComponent(ridN), "info");\n    html += linkPill("Unified.json", artUrl(ridN,"findings_unified.json"), "info");\n    html += linkPill("Effective.json", artUrl(ridN,"findings_effective.json"), "info");\n\n    bar.innerHTML = html;\n  }\n\n  // initial + refresh when RID changes (poll)\n  let lastRid="";\n  async function tick(){\n    const rid=getRid();\n    if(rid && rid!==lastRid){\n      lastRid=rid;\n      await render();\n    }\n  }\n\n  if(document.readyState==="loading"){\n    document.addEventListener("DOMContentLoaded", ()=>{ render(); setInterval(tick, 1200); });\n  }else{\n    render(); setInterval(tick, 1200);\n  }\n})();\n\n/* VSP_DASH_TREND_SPARKLINE_V1_BEGIN */\n(function(){\n  'use strict';\n  if (window.__VSP_DASH_TREND_SPARKLINE_V1_INSTALLED) return;\n  window.__VSP_DASH_TREND_SPARKLINE_V1_INSTALLED = true;\n\n  const LOGP = "[VSP_TREND]";\n  const API = "/api/vsp/runs_index_v3_fs_resolved?limit=20&hide_empty=0&filter=1";\n\n  function q(sel){ try{return document.querySelector(sel);}catch(e){return null;} }\n  function mountPoint(){\n    return (\n      q("#vsp4-dashboard") ||\n      q("#tab-dashboard") ||\n      q("[data-tab='dashboard']") ||\n      q("#dashboard") ||\n      q(".vsp-dashboard") ||\n      q("main") ||\n      document.body\n    );\n  }\n  function el(tag, attrs, children){\n    const n=document.createElement(tag);\n    if (attrs){\n      for (const k of Object.keys(attrs)){\n        if (k === "class") n.className = attrs[k];\n        else if (k === "style") n.setAttribute("style", attrs[k]);\n        else n.setAttribute(k, attrs[k]);\n      }\n    }\n    (children||[]).forEach(c=>{\n      if (c==null) return;\n      if (typeof c === "string") n.appendChild(document.createTextNode(c));\n      else n.appendChild(c);\n    });\n    return n;\n  }\n\n  function drawSpark(canvas, series){\n    if (!canvas) return;\n    const ctx = canvas.getContext("2d");\n    const w = canvas.width, h = canvas.height;\n    ctx.clearRect(0,0,w,h);\n\n    if (!Array.isArray(series) || series.length < 2){\n      ctx.globalAlpha = 0.6;\n      ctx.fillText("no data", 6, 14);\n      ctx.globalAlpha = 1;\n      return;\n    }\n    let min=Infinity, max=-Infinity;\n    for (const v of series){\n      if (typeof v !== "number" || !isFinite(v)) continue;\n      min = Math.min(min, v);\n      max = Math.max(max, v);\n    }\n    if (!isFinite(min) || !isFinite(max)){ min=0; max=1; }\n    if (max === min) max = min + 1;\n\n    const pad = 6;\n    const xStep = (w - pad*2) / (series.length - 1);\n    function y(v){\n      const t = (v - min) / (max - min);\n      return (h - pad) - t * (h - pad*2);\n    }\n\n    // mid grid\n    ctx.globalAlpha = 0.18;\n    ctx.beginPath();\n    ctx.moveTo(pad, Math.round(h/2)+0.5);\n    ctx.lineTo(w-pad, Math.round(h/2)+0.5);\n    ctx.stroke();\n    ctx.globalAlpha = 1;\n\n    // line\n    ctx.beginPath();\n    for (let i=0;i<series.length;i++){\n      const v = (typeof series[i] === "number" && isFinite(series[i])) ? series[i] : 0;\n      const xx = pad + i*xStep;\n      const yy = y(v);\n      if (i===0) ctx.moveTo(xx,yy);\n      else ctx.lineTo(xx,yy);\n    }\n    ctx.lineWidth = 2;\n    ctx.stroke();\n\n    // last dot\n    const lastV = (typeof series[series.length-1] === "number" && isFinite(series[series.length-1])) ? series[series.length-1] : 0;\n    ctx.beginPath();\n    ctx.arc(w-pad, y(lastV), 2.6, 0, Math.PI*2);\n    ctx.fill();\n  }\n\n  function fmtInt(n){ try { return (Number(n)||0).toLocaleString(); } catch(e){ return String(n||0); } }\n\n  async function run(){\n    try{\n      const res = await fetch(API, {cache:"no-store"});\n      if (!res.ok) { console.warn(LOGP, "runs_index not ok", res.status); return; }\n      const js = await res.json();\n      const items = (js && js.items) ? js.items : [];\n      if (!Array.isArray(items) || items.length === 0) return;\n\n      const rows = items.slice().reverse(); // old->new\n      const findings = rows.map(it => Number(it.total_findings ?? it.findings_total ?? it.total ?? 0) || 0);\n      const degraded = rows.map(it => {\n        const any = (it.degraded_any ?? it.is_degraded);\n        const dn = Number(it.degraded_n ?? it.degraded_count ?? 0) || 0;\n        return (any === true || dn > 0) ? 1 : 0;\n      });\n\n      const latest = rows[rows.length-1] || {};\n      const latestRid = latest.run_id || latest.id || "";\n\n      const root = mountPoint();\n      if (!root) return;\n      if (q("#vsp-trend-sparkline-card")) return;\n\n      const card = el("div", {\n        id: "vsp-trend-sparkline-card",\n        class: "vsp-card vsp-card-trend",\n        style: "margin-top:14px;border:1px solid rgba(148,163,184,.16);background:rgba(2,6,23,.72);border-radius:14px;padding:14px 14px 12px;box-shadow:0 10px 30px rgba(0,0,0,.25)"\n      });\n\n      const header = el("div", {style:"display:flex;justify-content:space-between;gap:12px;align-items:baseline;flex-wrap:wrap;"}, [\n        el("div", null, [\n          el("div", {style:"font-weight:700;font-size:14px;letter-spacing:.2px;"}, ["Trend (last 20 runs)"]),\n          el("div", {style:"opacity:.75;font-size:12px;margin-top:4px;"}, [\n            "Latest: ", latestRid ? latestRid : "(unknown)",\n            " • Findings: ", fmtInt(findings[findings.length-1]),\n            " • Degraded: ", degraded[degraded.length-1] ? "YES" : "NO"\n          ])\n        ])\n      ]);\n\n      const grid = el("div", {style:"display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:12px;"});\n      function panel(title, id){\n        const c = el("canvas", {id, width:"520", height:"88", style:"width:100%;height:88px;border-radius:12px;border:1px solid rgba(148,163,184,.12);background:rgba(15,23,42,.55);"});\n        const box = el("div", {style:"padding:10px 10px 8px;border-radius:12px;background:rgba(15,23,42,.35);border:1px solid rgba(148,163,184,.10);"}, [\n          el("div", {style:"font-size:12px;opacity:.8;margin-bottom:8px;font-weight:600;"}, [title]),\n          c\n        ]);\n        return {box, c};\n      }\n      const p1 = panel("Total Findings", "vsp-trend-findings");\n      const p2 = panel("Degraded (0/1)", "vsp-trend-degraded");\n      grid.appendChild(p1.box); grid.appendChild(p2.box);\n\n      card.appendChild(header);\n      card.appendChild(grid);\n\n      const anchor = q("#vsp-kpi-wrap") || q("#vsp-kpi-cards") || q(".vsp-kpi") || null;\n      if (anchor && anchor.parentElement) anchor.parentElement.insertBefore(card, anchor.nextSibling);\n      else root.appendChild(card);\n\n      try{\n        const css = window.getComputedStyle(card);\n        [p1.c, p2.c].forEach(cv=>{\n          const ctx=cv.getContext("2d");\n          ctx.strokeStyle = css.color || "#e5e7eb";\n          ctx.fillStyle = css.color || "#e5e7eb";\n        });\n      }catch(e){}\n\n      drawSpark(p1.c, findings);\n      drawSpark(p2.c, degraded);\n\n      p1.c.title = "Total Findings (old→new): " + findings.join(", ");\n      p2.c.title = "Degraded (old→new): " + degraded.join(", ");\n\n      console.log(LOGP, "trend rendered", {points: rows.length});\n    }catch(e){\n      console.warn(LOGP, "trend error", e);\n    }\n  }\n\n  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", run);\n  else run();\n})();\n /* VSP_DASH_TREND_SPARKLINE_V1_END */\n\n/* VSP_DASH_TREND_SPARKLINE_V2_BEGIN */\n(function(){\n  'use strict';\n\n  function $(sel){ return document.querySelector(sel); }\n  function el(tag, cls){ const e=document.createElement(tag); if(cls) e.className=cls; return e; }\n  function sstr(x){ return (typeof x === 'string') ? x.trim() : ''; }\n\n  function findKpiMount(){\n    // try common containers (robust across templates)\n    const cands = [\n      '#vsp-kpi-row', '#kpi-row', '#kpi-cards', '.vsp-kpi-row', '.kpi-row',\n      '.vsp-kpi-grid', '.kpi-grid', '.dashboard-kpis', '.dashboard-kpi-grid',\n      '.vsp-main .vsp-grid', '.vsp-main'\n    ];\n    for (const sel of cands){\n      const n = document.querySelector(sel);\n      if (n) return n;\n    }\n    // fallback: first large section in dashboard pane\n    return document.querySelector('#pane-dashboard, #tab-dashboard, main') || document.body;\n  }\n\n  async function fetchRuns(){\n    try{\n      const res = await fetch('/api/vsp/runs_index_v3_fs_resolved?limit=12&hide_empty=0&filter=1', {credentials:'same-origin'});\n      if (!res.ok) return [];\n      const js = await res.json();\n      return js.items || [];\n    }catch(_e){\n      return [];\n    }\n  }\n\n  function parseKeyFromRid(rid){\n    rid = sstr(rid);\n    const m = rid.match(/(\d{8})_(\d{6})/);\n    if (!m) return null;\n    return m[1] + m[2];\n  }\n\n  function buildSeries(items){\n    // sort ascending by rid timestamp\n    const arr = (items||[]).map(it=>{\n      const rid = sstr(it.run_id || it.rid || '');\n      const key = parseKeyFromRid(rid) || rid;\n      const v = Number(it.total_findings ?? it.findings_total ?? it.total ?? 0) || 0;\n      return {rid, key, v};\n    }).filter(x=>x.rid && x.key).sort((a,b)=> (a.key>b.key?1:(a.key<b.key?-1:0)));\n    // keep last 10\n    return arr.slice(Math.max(0, arr.length-10));\n  }\n\n  function drawSpark(canvas, series){\n    const ctx = canvas.getContext('2d');\n    const w = canvas.width, h = canvas.height;\n    ctx.clearRect(0,0,w,h);\n\n    if (!series || series.length < 2){\n      // empty state\n      ctx.globalAlpha = 0.5;\n      ctx.beginPath();\n      ctx.moveTo(6, h/2);\n      ctx.lineTo(w-6, h/2);\n      ctx.stroke();\n      ctx.globalAlpha = 1;\n      return;\n    }\n\n    const vals = series.map(x=>x.v);\n    let vmin = Math.min.apply(null, vals);\n    let vmax = Math.max.apply(null, vals);\n    if (vmax === vmin) vmax = vmin + 1;\n\n    const pad = 6;\n    const dx = (w - pad*2) / (series.length - 1);\n\n    ctx.lineWidth = 2;\n    ctx.beginPath();\n    for (let i=0;i<series.length;i++){\n      const v = series[i].v;\n      const x = pad + i*dx;\n      const y = pad + (h - pad*2) * (1 - (v - vmin) / (vmax - vmin));\n      if (i===0) ctx.moveTo(x,y); else ctx.lineTo(x,y);\n    }\n    ctx.stroke();\n\n    // end dot\n    const last = series[series.length-1].v;\n    const x = pad + (series.length-1)*dx;\n    const y = pad + (h - pad*2) * (1 - (last - vmin) / (vmax - vmin));\n    ctx.beginPath(); ctx.arc(x,y,3,0,Math.PI*2); ctx.fill();\n  }\n\n  function ensureCard(){\n    const id = 'vsp-trend-spark-card-v2';\n    let card = document.getElementById(id);\n    if (card) return card;\n\n    const mount = findKpiMount();\n\n    card = el('div', 'vsp-card dashboard-card');\n    card.id = id;\n    card.style.maxWidth = '420px';\n    card.style.padding = '12px 14px';\n    card.style.borderRadius = '14px';\n    card.style.margin = '8px 8px 8px 0';\n\n    const h = el('div');\n    h.style.display='flex';\n    h.style.justifyContent='space-between';\n    h.style.alignItems='baseline';\n    h.style.gap='10px';\n\n    const title = el('div');\n    title.innerHTML = '<div style="font-weight:700;letter-spacing:.2px">Trend (last 10)</div><div style="opacity:.7;font-size:12px">Total findings by run</div>';\n\n    const stat = el('div');\n    stat.id = 'vsp-trend-spark-stat-v2';\n    stat.style.textAlign='right';\n    stat.style.fontWeight='700';\n\n    h.appendChild(title);\n    h.appendChild(stat);\n\n    const canvas = el('canvas');\n    canvas.id = 'vsp-trend-spark-cv-v2';\n    canvas.width = 360;\n    canvas.height = 64;\n    canvas.style.width = '100%';\n    canvas.style.height = '64px';\n    canvas.style.marginTop = '10px';\n    canvas.style.borderRadius = '10px';\n\n    card.appendChild(h);\n    card.appendChild(canvas);\n\n    // prepend so it appears early\n    if (mount && mount.firstChild) mount.insertBefore(card, mount.firstChild);\n    else (mount || document.body).appendChild(card);\n\n    return card;\n  }\n\n  async function render(){\n    const card = ensureCard();\n    if (!card) return;\n\n    const items = await fetchRuns();\n    const series = buildSeries(items);\n\n    const stat = document.getElementById('vsp-trend-spark-stat-v2');\n    const cv = document.getElementById('vsp-trend-spark-cv-v2');\n\n    if (stat){\n      const n = series.length;\n      const last = n ? series[n-1].v : 0;\n      const prev = n>1 ? series[n-2].v : 0;\n      const delta = (n>1) ? (last - prev) : 0;\n      const pct = (n>1 && prev) ? (delta * 100.0 / prev) : 0;\n      stat.innerHTML = `<div style="font-size:16px">${last.toLocaleString()}</div><div style="opacity:.75;font-size:12px">${(delta>=0?'+':'')}${delta.toLocaleString()} (${(pct>=0?'+':'')}${pct.toFixed(1)}%)</div>`;\n    }\n    if (cv && cv.getContext) drawSpark(cv, series);\n  }\n\n  // run on dashboard load and also after refresh clicks\n  document.addEventListener('DOMContentLoaded', function(){\n    setTimeout(render, 650);\n    document.addEventListener('click', function(ev){\n      const t = ev.target;\n      if (!t) return;\n      const txt = (t.textContent||'').toLowerCase();\n      if (txt.includes('refresh')) setTimeout(render, 400);\n    }, true);\n  });\n})();\n /* VSP_DASH_TREND_SPARKLINE_V2_END */\n\n\n\n/* ==== END static/js/vsp_dashboard_enhance_v1.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_dashboard_charts_pretty_v3.js ==== */\n\n/* vsp_dashboard_charts_pretty_v3.js\n * CLEAN REBUILD (no Chart.js dependency)\n * - Exports: window.VSP_CHARTS_ENGINE_V3.initAll(dash)\n * - Auto-creates canvases inside placeholders:\n *     #vsp-chart-severity, #vsp-chart-trend, #vsp-chart-bytool, #vsp-chart-topcwe\n * - Dispatches: window event "vsp:charts-ready"\n */\n(function () {\n  "use strict";\n  console.log("[VSP_CHARTS_V3] pretty charts loaded (CLEAN REBUILD v1)");\n\n  if (window.__VSP_CHARTS_V3_REBUILD_LOADED) return;\n  window.__VSP_CHARTS_V3_REBUILD_LOADED = true;\n\n  var HOLDERS = {\n    severity: "vsp-chart-severity",\n    trend: "vsp-chart-trend",\n    bytool: "vsp-chart-bytool",\n    topcwe: "vsp-chart-topcwe"\n  };\n\n  function $(id) { return document.getElementById(id); }\n\n  function ensureCanvasIn(holderId, canvasId) {\n    var holder = $(holderId);\n    if (!holder) return null;\n\n    // if holder itself is a canvas\n    if (holder.tagName && holder.tagName.toLowerCase() === "canvas") return holder;\n\n    // existing canvas?\n    var existing = holder.querySelector ? holder.querySelector("canvas") : null;\n    if (existing) return existing;\n\n    var c = document.createElement("canvas");\n    c.id = canvasId;\n    c.style.width = "100%";\n    c.style.height = "100%";\n    c.width = Math.max(480, holder.clientWidth || 480);\n    c.height = Math.max(220, holder.clientHeight || 220);\n    holder.appendChild(c);\n    return c;\n  }\n\n  function resizeCanvasToHolder(canvas, holderId) {\n    try {\n      var holder = $(holderId);\n      if (!holder || !canvas) return;\n      var w = Math.max(480, holder.clientWidth || 480);\n      var h = Math.max(220, holder.clientHeight || 220);\n      if (canvas.width !== w) canvas.width = w;\n      if (canvas.height !== h) canvas.height = h;\n    } catch (e) {}\n  }\n\n  function clear(ctx) {\n    ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);\n  }\n\n  function drawText(ctx, text) {\n    clear(ctx);\n    ctx.save();\n    ctx.fillStyle = "#cbd5e1";\n    ctx.font = "14px Inter, system-ui, sans-serif";\n    ctx.textAlign = "center";\n    ctx.textBaseline = "middle";\n    ctx.fillText(text, ctx.canvas.width / 2, ctx.canvas.height / 2);\n    ctx.restore();\n  }\n\n  function drawDonut(ctx, items) {\n    // items: [{label, value}]\n    clear(ctx);\n    var W = ctx.canvas.width, H = ctx.canvas.height;\n    var cx = W * 0.35, cy = H * 0.5;\n    var rOuter = Math.min(W, H) * 0.28;\n    var rInner = rOuter * 0.58;\n\n    var sum = 0;\n    for (var i=0;i<items.length;i++) sum += Math.max(0, +items[i].value || 0);\n    if (!sum) return drawText(ctx, "No data");\n\n    // palette (no hard theme dependency)\n    var palette = ["#ef4444","#f97316","#f59e0b","#22c55e","#60a5fa","#a78bfa","#94a3b8"];\n    var start = -Math.PI / 2;\n\n    for (var j=0;j<items.length;j++) {\n      var v = Math.max(0, +items[j].value || 0);\n      var ang = (v / sum) * Math.PI * 2;\n      ctx.beginPath();\n      ctx.moveTo(cx, cy);\n      ctx.arc(cx, cy, rOuter, start, start + ang, false);\n      ctx.closePath();\n      ctx.fillStyle = palette[j % palette.length];\n      ctx.globalAlpha = 0.85;\n      ctx.fill();\n      start += ang;\n    }\n    ctx.globalAlpha = 1;\n\n    // hole\n    ctx.beginPath();\n    ctx.arc(cx, cy, rInner, 0, Math.PI * 2);\n    ctx.fillStyle = "#0b1020";\n    ctx.fill();\n\n    // total\n    ctx.save();\n    ctx.fillStyle = "#e5e7eb";\n    ctx.font = "700 18px Inter, system-ui, sans-serif";\n    ctx.textAlign = "center";\n    ctx.textBaseline = "middle";\n    ctx.fillText(String(sum), cx, cy - 2);\n    ctx.font = "12px Inter, system-ui, sans-serif";\n    ctx.fillStyle = "#94a3b8";\n    ctx.fillText("total", cx, cy + 18);\n    ctx.restore();\n\n    // legend\n    var lx = W * 0.62, ly = H * 0.22;\n    ctx.save();\n    ctx.font = "12px Inter, system-ui, sans-serif";\n    ctx.textAlign = "left";\n    ctx.textBaseline = "middle";\n    for (var k=0;k<items.length;k++) {\n      var y = ly + k * 18;\n      ctx.fillStyle = palette[k % palette.length];\n      ctx.globalAlpha = 0.85;\n      ctx.fillRect(lx, y - 6, 10, 10);\n      ctx.globalAlpha = 1;\n      ctx.fillStyle = "#cbd5e1";\n      ctx.fillText(items[k].label + ": " + (items[k].value || 0), lx + 14, y);\n    }\n    ctx.restore();\n  }\n\n  function drawBar(ctx, items, title) {\n    clear(ctx);\n    var W = ctx.canvas.width, H = ctx.canvas.height;\n    if (!items || !items.length) return drawText(ctx, "No data");\n\n    var max = 0;\n    for (var i=0;i<items.length;i++) max = Math.max(max, +items[i].value || 0);\n    if (!max) return drawText(ctx, "No data");\n\n    var padL=48, padR=16, padT=28, padB=28;\n    var plotW = W - padL - padR;\n    var plotH = H - padT - padB;\n\n    ctx.save();\n    ctx.fillStyle = "#94a3b8";\n    ctx.font = "12px Inter, system-ui, sans-serif";\n    ctx.textAlign = "left";\n    ctx.fillText(title || "Bar", padL, 18);\n    ctx.restore();\n\n    // axes\n    ctx.save();\n    ctx.strokeStyle = "rgba(255,255,255,0.08)";\n    ctx.beginPath();\n    ctx.moveTo(padL, padT);\n    ctx.lineTo(padL, padT + plotH);\n    ctx.lineTo(padL + plotW, padT + plotH);\n    ctx.stroke();\n    ctx.restore();\n\n    var n = items.length;\n    var gap = Math.max(6, plotW * 0.02);\n    var bw = (plotW - gap * (n - 1)) / n;\n\n    for (var j=0;j<n;j++) {\n      var v = +items[j].value || 0;\n      var h = (v / max) * plotH;\n      var x = padL + j * (bw + gap);\n      var y = padT + (plotH - h);\n\n      ctx.fillStyle = "rgba(96,165,250,0.75)";\n      ctx.fillRect(x, y, bw, h);\n\n      ctx.save();\n      ctx.fillStyle = "#cbd5e1";\n      ctx.font = "11px Inter, system-ui, sans-serif";\n      ctx.textAlign = "center";\n      ctx.textBaseline = "top";\n      var lab = items[j].label;\n      if (lab && lab.length > 10) lab = lab.slice(0, 9) + "…";\n      ctx.fillText(lab || "", x + bw/2, padT + plotH + 6);\n      ctx.restore();\n    }\n  }\n\n  function drawLine(ctx, series, title) {\n    clear(ctx);\n    var W = ctx.canvas.width, H = ctx.canvas.height;\n    if (!series || series.length < 2) return drawText(ctx, "No trend data");\n\n    var padL=48, padR=16, padT=28, padB=28;\n    var plotW = W - padL - padR;\n    var plotH = H - padT - padB;\n\n    var min=Infinity, max=-Infinity;\n    for (var i=0;i<series.length;i++) {\n      var v = +series[i].value || 0;\n      min = Math.min(min, v);\n      max = Math.max(max, v);\n    }\n    if (max === min) { max = min + 1; }\n\n    ctx.save();\n    ctx.fillStyle = "#94a3b8";\n    ctx.font = "12px Inter, system-ui, sans-serif";\n    ctx.textAlign = "left";\n    ctx.fillText(title || "Trend", padL, 18);\n    ctx.restore();\n\n    // axes\n    ctx.save();\n    ctx.strokeStyle = "rgba(255,255,255,0.08)";\n    ctx.beginPath();\n    ctx.moveTo(padL, padT);\n    ctx.lineTo(padL, padT + plotH);\n    ctx.lineTo(padL + plotW, padT + plotH);\n    ctx.stroke();\n    ctx.restore();\n\n    function px(i) {\n      return padL + (i / (series.length - 1)) * plotW;\n    }\n    function py(v) {\n      return padT + (1 - (v - min) / (max - min)) * plotH;\n    }\n\n    ctx.save();\n    ctx.strokeStyle = "rgba(34,197,94,0.85)";\n    ctx.lineWidth = 2;\n    ctx.beginPath();\n    ctx.moveTo(px(0), py(series[0].value));\n    for (var j=1;j<series.length;j++) {\n      ctx.lineTo(px(j), py(series[j].value));\n    }\n    ctx.stroke();\n\n    // points\n    ctx.fillStyle = "rgba(34,197,94,0.9)";\n    for (var k=0;k<series.length;k++) {\n      ctx.beginPath();\n      ctx.arc(px(k), py(series[k].value), 3, 0, Math.PI*2);\n      ctx.fill();\n    }\n    ctx.restore();\n  }\n\n  function normalizeSeverity(dash) {\n    var s = (dash && dash.by_severity) ? dash.by_severity : {};\n    // accept either VSP levels or generic\n    var keys = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];\n    var out = [];\n    for (var i=0;i<keys.length;i++) {\n      var k = keys[i];\n      var v = 0;\n      if (typeof s[k] === "number") v = s[k];\n      else if (s[k] && typeof s[k].count === "number") v = s[k].count;\n      out.push({ label: k, value: v });\n    }\n    return out;\n  }\n\n  function normalizeByTool(dash) {\n    var bt = (dash && dash.by_tool) ? dash.by_tool : {};\n    var items = [];\n    // bt could be {tool:count} or {tool:{total}} etc.\n    for (var k in bt) {\n      if (!Object.prototype.hasOwnProperty.call(bt, k)) continue;\n      var v = bt[k];\n      var n = (typeof v === "number") ? v :\n              (v && typeof v.total === "number") ? v.total :\n              (v && typeof v.count === "number") ? v.count : 0;\n      items.push({ label: k, value: n });\n    }\n    items.sort(function(a,b){ return (b.value||0) - (a.value||0); });\n    return items.slice(0, 6);\n  }\n\n  function normalizeTopCWE(dash) {\n    var list = (dash && dash.top_cwe_list) ? dash.top_cwe_list : [];\n    var items = [];\n    for (var i=0;i<list.length;i++) {\n      var x = list[i] || {};\n      var lab = x.cwe || x.id || x.name || ("CWE-" + (i+1));\n      var v = x.count || x.n || x.total || 0;\n      items.push({ label: String(lab), value: +v || 0 });\n    }\n    items.sort(function(a,b){ return (b.value||0)-(a.value||0); });\n    return items.slice(0, 6);\n  }\n\n  function normalizeTrend(dash) {\n    // If no historical series, create a tiny synthetic series from totals\n    var total = (dash && dash.total_findings) ? +dash.total_findings :\n                (dash && dash.summary_all && dash.summary_all.total_findings) ? +dash.summary_all.total_findings :\n                (dash && dash.totals && dash.totals.total) ? +dash.totals.total : 0;\n    if (!total) total = 0;\n    return [\n      { label: "t-3", value: Math.max(0, Math.round(total*0.55)) },\n      { label: "t-2", value: Math.max(0, Math.round(total*0.72)) },\n      { label: "t-1", value: Math.max(0, Math.round(total*0.88)) },\n      { label: "now", value: total }\n    ];\n  }\n\n  function dispatchReady(detail) {\n    try {\n      window.dispatchEvent(new CustomEvent("vsp:charts-ready", { detail: detail || { engine:"V3", ts: Date.now() } }));\n    } catch (e) {\n      try {\n        var ev = document.createEvent("Event");\n        ev.initEvent("vsp:charts-ready", true, true);\n        window.dispatchEvent(ev);\n      } catch (_) {}\n    }\n  }\n\n  window.VSP_CHARTS_ENGINE_V3 = {\n    initAll: function (dash) {\n      try {\n        // create canvases and render\n        var cSev = ensureCanvasIn(HOLDERS.severity, "vsp-severity-canvas");\n        var cTr  = ensureCanvasIn(HOLDERS.trend, "vsp-trend-canvas");\n        var cBt  = ensureCanvasIn(HOLDERS.bytool, "vsp-bytool-canvas");\n        var cCwe = ensureCanvasIn(HOLDERS.topcwe, "vsp-topcwe-canvas");\n\n        if (cSev) resizeCanvasToHolder(cSev, HOLDERS.severity);\n        if (cTr)  resizeCanvasToHolder(cTr,  HOLDERS.trend);\n        if (cBt)  resizeCanvasToHolder(cBt,  HOLDERS.bytool);\n        if (cCwe) resizeCanvasToHolder(cCwe, HOLDERS.topcwe);\n\n        if (cSev) drawDonut(cSev.getContext("2d"), normalizeSeverity(dash));\n        if (cTr)  drawLine(cTr.getContext("2d"), normalizeTrend(dash), "Findings trend (synthetic)");\n        if (cBt)  drawBar(cBt.getContext("2d"), normalizeByTool(dash), "Top tools");\n        if (cCwe) drawBar(cCwe.getContext("2d"), normalizeTopCWE(dash), "Top CWE");\n\n        console.log("[VSP_CHARTS_V3] initAll OK");\n        return true;\n      } catch (e) {\n        console.warn("[VSP_CHARTS_V3] initAll failed", e);\n        return false;\n      }\n    }\n  };\n\n  // Auto-init if dashboard already stored data\n  try {\n    if (window.__VSP_DASH_LAST_DATA_V3) {\n      window.VSP_CHARTS_ENGINE_V3.initAll(window.__VSP_DASH_LAST_DATA_V3);\n    }\n  } catch (e) {}\n\n  // Inform other modules (dashboard enhance) that charts engine is ready\n  dispatchReady({ engine: "V3", ts: Date.now() });\n\n  // Re-render on resize (lightweight)\n  window.addEventListener("resize", function () {\n    try {\n      if (window.__VSP_DASH_LAST_DATA_V3) {\n        window.VSP_CHARTS_ENGINE_V3.initAll(window.__VSP_DASH_LAST_DATA_V3);\n      }\n    } catch (e) {}\n  });\n\n})();\n\n// === VSP_CHARTS_READY_EVENT_V1 ===\n\n(function(){\n  try{\n    if (window.__VSP_CHARTS_READY_EVENT_V1) return;\n    window.__VSP_CHARTS_READY_EVENT_V1 = true;\n    window.dispatchEvent(new CustomEvent('vsp:charts-ready', { detail: { engine: 'V3' } }));\n    console.log('[VSP_CHARTS] vsp:charts-ready dispatched (V3).');\n  }catch(e){}\n})();\n\n\n\n/* ==== END static/js/vsp_dashboard_charts_pretty_v3.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_dashboard_charts_bootstrap_v1.js ==== */\n\n/* VSP_DASHBOARD_CHARTS_BOOTSTRAP_V1 (P0 commercial v2)\n * - bounded retries\n * - always attempts initAll (even if container heuristic fails)\n * - empty-state has safe fallback mount (main/body) => no "missing chart container" warn\n */\n(function(){\n  'use strict';\n\n  if (window.__VSP_CHARTS_BOOT_SAFE_V4) return;\n  window.__VSP_CHARTS_BOOT_SAFE_V4 = true;\n\n  const TAG = 'VSP_CHARTS_BOOT_SAFE_V4';\n  const MAX_TRIES = 8;\n  const BASE_DELAY_MS = 250;\n\n  let tries = 0;\n  let locked = false;\n  let lastReason = '';\n  let warnedOnce = false;\n\n  const SELS = [\n    '#vsp_charts_root',\n    '#vsp_charts_container',\n    '#vsp-dashboard-charts',\n    '#dashboard_charts',\n    '#charts_container',\n    '#chart-container',\n    '.vsp-charts',\n    '[data-vsp-charts]',\n    '[data-vsp-charts-root]'\n  ];\n\n  function nowISO(){ try { return new Date().toISOString(); } catch(_) { return ''; } }\n\n  function esc(s){\n    return String(s ?? '')\n      .replaceAll('&','&amp;')\n      .replaceAll('<','&lt;')\n      .replaceAll('>','&gt;')\n      .replaceAll('"','&quot;')\n      .replaceAll("'","&#039;");\n  }\n\n  function pickMount(){\n    // 1) explicit known selectors\n    for (const s of SELS){\n      const el = document.querySelector(s);\n      if (el) return el;\n    }\n\n    // 2) heuristic: find chart cards by common classes\n    const card = document.querySelector('.vsp-card .chart, .dashboard-card .chart, .vsp-card, .dashboard-card');\n    if (card) return card;\n\n    // 3) safe fallback: main/app/root/body (commercial: always render somewhere)\n    return document.querySelector('main') ||\n           document.querySelector('#app') ||\n           document.querySelector('#root') ||\n           document.body;\n  }\n\n  function ensureStyles(){\n    if (document.getElementById('vsp-charts-empty-style-v2')) return;\n    const st = document.createElement('style');\n    st.id = 'vsp-charts-empty-style-v2';\n    st.textContent = `\n      .vsp-charts-empty{border:1px solid rgba(255,255,255,.10);background:rgba(255,255,255,.03);\n        border-radius:14px;padding:14px;margin-top:10px}\n      .vsp-charts-empty-hd{display:flex;align-items:center;justify-content:space-between;gap:10px}\n      .vsp-charts-empty-title{font-weight:800;letter-spacing:.2px}\n      .vsp-charts-empty-sub{margin-top:6px;font-size:12px;opacity:.85;display:grid;gap:4px}\n      .vsp-charts-empty-reason{font-size:12px;opacity:.75}\n      .vsp-charts-empty-btn{margin-top:10px;display:inline-flex;align-items:center;gap:8px;\n        padding:7px 10px;border-radius:999px;border:1px solid rgba(255,255,255,.14);\n        background:rgba(255,255,255,.06);cursor:pointer;font-weight:700;font-size:12px}\n      .vsp-charts-empty-btn:hover{background:rgba(255,255,255,.10)}\n      .vsp-charts-empty-pill{font-size:12px;font-weight:900;padding:5px 10px;border-radius:999px;\n        border:1px solid rgba(255,255,255,.12);background:rgba(255,190,0,.14)}\n    `;\n    document.head.appendChild(st);\n  }\n\n  function renderEmptyState(reason){\n    ensureStyles();\n    const mount = pickMount();\n\n    const html = `\n      <div class="vsp-charts-empty" data-vsp-charts-empty="1">\n        <div class="vsp-charts-empty-hd">\n          <div class="vsp-charts-empty-title">Charts</div>\n          <div class="vsp-charts-empty-pill">WAITING</div>\n        </div>\n        <div class="vsp-charts-empty-sub">\n          <div class="vsp-charts-empty-reason">${esc(reason || 'waiting for chart data')}</div>\n          <div>Updated: ${esc(nowISO())}</div>\n        </div>\n        <button class="vsp-charts-empty-btn" type="button" id="vspChartsRetryBtn">Retry charts</button>\n      </div>\n    `;\n\n    const existing = mount.querySelector ? mount.querySelector('[data-vsp-charts-empty="1"]') : null;\n    if (existing){\n      const rr = existing.querySelector('.vsp-charts-empty-reason');\n      if (rr) rr.textContent = reason || 'waiting for chart data';\n    } else if (mount && mount.prepend){\n      const w = document.createElement('div');\n      w.innerHTML = html;\n      mount.prepend(w.firstElementChild);\n    }\n\n    const btn = (mount && mount.querySelector) ? mount.querySelector('#vspChartsRetryBtn') : null;\n    if (btn && !btn.__bound){\n      btn.__bound = true;\n      btn.addEventListener('click', function(){\n        tries = 0; locked = false;\n        scheduleTry('manual retry');\n      });\n    }\n  }\n\n  function clearEmptyState(){\n    const mount = pickMount();\n    const el = (mount && mount.querySelector) ? mount.querySelector('[data-vsp-charts-empty="1"]') : null;\n    if (el) el.remove();\n  }\n\n  function pickEngine(){\n    if (window.VSP_CHARTS_ENGINE_V3 && typeof window.VSP_CHARTS_ENGINE_V3.initAll === 'function'){\n      return { tag:'VSP_CHARTS_ENGINE_V3', eng: window.VSP_CHARTS_ENGINE_V3 };\n    }\n    if (window.VSP_CHARTS_ENGINE && typeof window.VSP_CHARTS_ENGINE.initAll === 'function'){\n      return { tag:'VSP_CHARTS_ENGINE', eng: window.VSP_CHARTS_ENGINE };\n    }\n    if (typeof window.vspChartsInitAll === 'function'){\n      return { tag:'window.vspChartsInitAll', eng: { initAll: window.vspChartsInitAll } };\n    }\n    return null;\n  }\n\n  function computeDelay(n){ return Math.min(1200, BASE_DELAY_MS + (n * 120)); }\n\n  async function tryInit(reasonTag){\n    if (locked) return false;\n    locked = true;\n    tries += 1;\n\n    const pe = pickEngine();\n    if (!pe){\n      lastReason = 'charts module not loaded (engine missing)';\n      locked = false;\n      return false;\n    }\n\n    try{\n      pe.eng.initAll(reasonTag || TAG);\n      clearEmptyState();\n      console.log(`[${TAG}] initAll OK via`, pe.tag, 'tries=', tries);\n      return true;\n    }catch(e){\n      lastReason = `initAll failed: ${e && e.message ? e.message : String(e)}`;\n      if (!warnedOnce){\n        warnedOnce = true;\n        console.warn(`[${TAG}] initAll failed (bounded retry)`, e);\n      }\n      locked = false;\n      return false;\n    }\n  }\n\n  function scheduleTry(tag){\n    const delay = computeDelay(tries);\n    setTimeout(async () => {\n      const ok = await tryInit(tag);\n      if (ok) return;\n\n      if (tries >= MAX_TRIES){\n        renderEmptyState(lastReason || `no chart data (tries=${tries}/${MAX_TRIES})`);\n        console.log(`[${TAG}] done: empty-state shown; tries=${tries}/${MAX_TRIES}; reason=`, lastReason);\n        return;\n      }\n\n      renderEmptyState(lastReason || `waiting for chart data (tries=${tries}/${MAX_TRIES})`);\n      scheduleTry(tag);\n    }, delay);\n  }\n\n  function boot(){\n    tries = 0; locked = false; lastReason = ''; warnedOnce = false;\n    scheduleTry('boot');\n  }\n\n  window.VSP_CHARTS_BOOT_SAFE_V4 = { boot, refresh: () => scheduleTry('refresh') };\n\n  if (document.readyState === 'loading'){\n    document.addEventListener('DOMContentLoaded', boot, { once:true });\n  } else {\n    boot();\n  }\n\n  window.addEventListener('vsp:rid_changed', () => scheduleTry('rid_changed'));\n})();\n\n\n/* ==== END static/js/vsp_dashboard_charts_bootstrap_v1.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_dashboard_charts_v1.js ==== */\n\n\nfunction vspNormalizeTopModule(m) {\n  if (!m) return 'N/A';\n  if (typeof m === 'string') return m;\n  try {\n    if (m.label) return String(m.label);\n    if (m.path) return String(m.path);\n    if (m.id)   return String(m.id);\n    return String(m);\n  } catch (e) {\n    return 'N/A';\n  }\n}\n\n'use strict';\n\n(function () {\n  const LOG = '[VSP_DASHBOARD_CHARTS]';\n\n  function percent(part, total) {\n    if (!total || total <= 0) return 0;\n    return Math.round((part * 100) / total);\n  }\n\n  function renderSeverity(model) {\n    const host = document.getElementById('vsp-chart-severity');\n    if (!host) return;\n\n    const sev =\n      model.severity_cards ||\n      model.summary_by_severity ||\n      {};\n    const total =\n      model.total_findings ??\n      model.total ??\n      0;\n\n    const order = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFO', 'TRACE'];\n    const labels = {\n      CRITICAL: 'Critical',\n      HIGH: 'High',\n      MEDIUM: 'Medium',\n      LOW: 'Low',\n      INFO: 'Info',\n      TRACE: 'Trace'\n    };\n\n    const rows = order.map(k => {\n      const v = sev[k] ?? 0;\n      const p = percent(v, total);\n      return `\n        <div class="vsp-chart-row">\n          <div class="vsp-chart-label">${labels[k]}</div>\n          <div class="vsp-chart-bar-wrap">\n            <div class="vsp-chart-bar" style="width:${p}%;"></div>\n          </div>\n          <div class="vsp-chart-value">${v} (${p}%)</div>\n        </div>\n      `;\n    }).join('');\n\n    host.innerHTML = rows || '<div class="vsp-chart-empty">Chưa có dữ liệu severity.</div>';\n  }\n\n  function renderTopTool(model) {\n    const host = document.getElementById('vsp-chart-tool');\n    if (!host) return;\n\n    const top = model.top_risky_tool_detail || model.top_risky_tool;\n    if (!top || typeof top === 'string') {\n      host.innerHTML = '<div class="vsp-chart-empty">Dữ liệu chi tiết theo tool chưa sẵn có.</div>';\n      return;\n    }\n\n    const entries = Array.isArray(top) ? top : Object.entries(top);\n\n    const rows = entries.map(([name, count]) => {\n      const v = typeof count === 'number' ? count : (count.total || 0);\n      return `\n        <div class="vsp-chart-row">\n          <div class="vsp-chart-label">${name}</div>\n          <div class="vsp-chart-bar-wrap">\n            <div class="vsp-chart-bar" style="width:100%;"></div>\n          </div>\n          <div class="vsp-chart-value">${v}</div>\n        </div>\n      `;\n    }).join('');\n\n    host.innerHTML = rows || '<div class="vsp-chart-empty">Không có dữ liệu tool.</div>';\n  }\n\n  function renderTopCwe(model) {\n    const host = document.getElementById('vsp-chart-cwe');\n    if (!host) return;\n\n    const top = model.top_cwe_detail || model.top_impacted_cwe;\n    if (!top || typeof top === 'string') {\n      host.innerHTML = '<div class="vsp-chart-empty">Dữ liệu chi tiết theo CWE chưa sẵn có.</div>';\n      return;\n    }\n\n    const entries = Array.isArray(top) ? top : Object.entries(top);\n\n    const rows = entries.map(([name, count]) => {\n      const v = typeof count === 'number' ? count : (count.total || 0);\n      return `\n        <div class="vsp-chart-row">\n          <div class="vsp-chart-label">${name}</div>\n          <div class="vsp-chart-bar-wrap">\n            <div class="vsp-chart-bar" style="width:100%;"></div>\n          </div>\n          <div class="vsp-chart-value">${v}</div>\n        </div>\n      `;\n    }).join('');\n\n    host.innerHTML = rows || '<div class="vsp-chart-empty">Không có dữ liệu CWE.</div>';\n  }\n\n  function render(model) {\n    if (!model) return;\n    console.log(LOG, 'Render charts from model');\n    renderSeverity(model);\n    renderTopTool(model);\n    renderTopCwe(model);\n  }\n\n  window.vspRenderChartsFromDashboard = render;\n\n  document.addEventListener('DOMContentLoaded', function () {\n    if (window.VSP_DASHBOARD_MODEL) {\n      render(window.VSP_DASHBOARD_MODEL);\n    }\n  });\n})();\n\n\n/* ==== END static/js/vsp_dashboard_charts_v1.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_dashboard_charts_v2.js ==== */\n\n// VSP_DASHBOARD_CHARTS_V2_STUB\n// Legacy charts_v2 đã được thay bằng pretty_v3.\n\n(function () {\n  console.log('[VSP_CHARTS_V2_STUB] legacy charts_v2 replaced by pretty_v3');\n\n  function forwardToV3(dashboard) {\n    if (window.VSP_DASHBOARD_CHARTS_V3 &&\n        typeof window.VSP_DASHBOARD_CHARTS_V3.updateFromDashboard === 'function') {\n      try {\n        window.VSP_DASHBOARD_CHARTS_V3.updateFromDashboard(dashboard);\n      } catch (e) {\n        console.error('[VSP_CHARTS_V2_STUB] error in V3 charts', e);\n      }\n    } else {\n      console.warn('[VSP_CHARTS_V2_STUB] V3 charts chưa sẵn, skip.');\n    }\n  }\n\n  // Global API mà vsp_dashboard_enhance_v1.js dùng\n  window.VSP_DASHBOARD_CHARTS = window.VSP_DASHBOARD_CHARTS || {};\n  window.VSP_DASHBOARD_CHARTS.updateFromDashboard = forwardToV3;\n  window.vspDashboardChartsUpdateFromDashboard = forwardToV3;\n})();\n\n\n/* ==== END static/js/vsp_dashboard_charts_v2.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_dashboard_cleanup_v1.js ==== */\n\n// static/js/vsp_dashboard_cleanup_v1.js\n// TẠM THỜI VÔ HIỆU – không ẩn gì hết, chỉ log cho dễ debug.\n\n(function () {\n  'use strict';\n  console.log('[VSP_DASH_CLEANUP] disabled – no legacy block is hidden.');\n})();\n\n\n/* ==== END static/js/vsp_dashboard_cleanup_v1.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_dashboard_comm_enhance_v1.js ==== */\n\n// VSP_SAFE_DRILLDOWN_HARDEN_P0_V6\n\n  // VSP_DD_LOCAL_SAFE_VAR_V1: force local callable symbol (prevents TypeError forever)\n  try{\n    function __vsp_dd_stub_local(){\n      try{ console.info("[VSP][DD] local-safe stub invoked"); }catch(_){}\n      return {open:function(){},show:function(){},close:function(){},destroy:function(){}};\n    }\n    try{\n      if (typeof window !== "undefined") {\n\n\n/* VSP_FIX_DRILLDOWN_ARTIFACTS_NOT_FUNCTION_P0_V2\n * Fix: TypeError __VSP_DD_ART_CALL__(VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2, ...) is not a function\n * Normalize BEFORE first use:\n *   - if function: keep\n *   - if object with .open(): wrap as function(arg)->obj.open(arg)\n *   - else: no-op (never throw)\n */\n(function(){\n  'use strict';\n  \n\n\n\n/* VSP_FIX_DRILLDOWN_CALLSITE_P0_V5: safe-call drilldown artifacts (function OR object.open) */\nfunction __VSP_DD_ART_CALL__(h, ...args) {\n  try {\n    if (typeof h === 'function') return h(...args);\n    if (h && typeof h.open === 'function') return h.open(...args);\n  } catch(e) { try{console.warn('[VSP][DD_SAFE]', e);}catch(_e){} }\n  return null;\n}\n\n/* VSP_FIX_DRILLDOWN_CALLSITE_P0_V3: safe-call for drilldown artifacts (function OR object.open) */\nfunction __VSP_DD_ART_CALL__(h, ...args) {\n  try {\n    if (typeof h === 'function') return h(...args);\n    if (h && typeof h.open === 'function') return h.open(...args);\n  } catch (e) {\n    try { console.warn('[VSP][DD_SAFE] call failed', e); } catch (_e) {}\n  }\n  return null;\n}\n\nif (window.__VSP_FIX_DRILLDOWN_ARTIFACTS_NOT_FUNCTION_P0_V2) return;\n  window.__VSP_FIX_DRILLDOWN_ARTIFACTS_NOT_FUNCTION_P0_V2 = 1;\n\n  function normalize(v){\n    if (typeof v === 'function') return v;\n    if (v && typeof v.open === 'function') {\n      const obj = v;\n      const fn = function(arg){ try { return obj.open(arg); } catch(e){ console.warn('[VSP][DD_FIX] open() failed', e); return null; } };\n      fn.__wrapped_from_object = true;\n      return fn;\n    }\n    const noop = function(_arg){ return null; };\n    noop.__noop = true;\n    return noop;\n  }\n\n  try {\n    // trap future assignments\n    let _val = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;\n    Object.defineProperty(window, 'VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2', {\n      configurable: true, enumerable: true,\n      get: function(){ return _val; },\n      set: function(v){ _val = normalize(v); }\n    });\n    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = _val;\n  } catch(e) {\n    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = normalize(window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2);\n  }\n})();\n\n        if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {\n          window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = __vsp_dd_stub_local;\n        }\n      }\n    }catch(_){}\n    // IMPORTANT: bind a LOCAL var used by this file (so later overwrites can't break us)\n    var VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 =\n      (typeof window !== "undefined" && typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 === "function")\n        ? window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\n        : __vsp_dd_stub_local;\n  }catch(_){}\n\n  // VSP_DD_CALLSAFE_P0_V2: ALWAYS call window drilldown as function, never crash\n  function __VSP_DD_CALL__(/*...args*/){\n    try{\n      var fn = (typeof window !== "undefined" && typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 === "function")\n        ? window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\n        : function(){ return {open:function(){},show:function(){},close:function(){},destroy:function(){}}; };\n      return fn.apply(null, arguments);\n    }catch(_){\n      return {open:function(){},show:function(){},close:function(){},destroy:function(){}};\n    }\n  }\n\n  // VSP_DD_GUARD_LOCAL_V1: never crash if drilldown symbol isn't a function\n  try{\n    function __vsp_dd_stub(){\n      try{ console.info("[VSP][DD] local stub invoked"); }catch(_){}\n      return {open:function(){},show:function(){},close:function(){},destroy:function(){}};\n    }\n    if (typeof window !== "undefined") {\n      if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {\n        window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = __vsp_dd_stub;\n      }\n    }\n  }catch(_){}\n"use strict";\n\n/**\n * VSP_DASHBOARD_COMM_ENHANCE_V1\n * - Bổ sung KPI cho TAB 2 (Runs & Reports): Total runs + Last run timestamp\n * - Đổ bảng Run index vào #vsp-runs-container\n * - Đổ bảng Data Source (severity + theo tool) vào #vsp-datasource-container\n */\n(function () {\n  function formatTs(ts) {\n    if (!ts) return "–";\n    return String(ts).replace("T", " ").split(".")[0];\n  }\n\n  /* ======================\n   *  RUNS & REPORTS (TAB 2)\n   * ====================== */\n  function renderRuns(data) {\n    var container = document.getElementById("vsp-runs-container");\n    if (!container) return;\n\n    var items;\n    if (Array.isArray(data)) {\n      items = data;\n    } else if (data && Array.isArray(data.items)) {\n      items = data.items;\n    } else {\n      items = [];\n    }\n\n    if (!items.length) {\n      container.innerHTML =\n        '<p style="font-size:12px;color:#9ca3c7;">Không tải được dữ liệu runs.</p>';\n      return;\n    }\n\n    // KPI: total runs + last run timestamp\n    var totalRuns = items.length;\n    var latest = items[0] || {};\n    var kpiCards = document.querySelectorAll("#tab-runs .kpi-value");\n    if (kpiCards[0]) {\n      kpiCards[0].textContent = String(totalRuns);\n    }\n    if (kpiCards[1]) {\n      kpiCards[1].textContent = formatTs(latest.ts || latest.ts_last_run);\n    }\n\n    // Bảng Run index\n    var html = '';\n    html += '<div style="max-height: 320px; overflow:auto;">';\n    html += '<table class="vsp-table">';\n    html += '<thead><tr>';\n    html += '<th>Run ID</th>';\n    html += '<th>Total</th>';\n    html += '<th>CRI</th>';\n    html += '<th>HIGH</th>';\n    html += '<th>MED</th>';\n    html += '<th>LOW</th>';\n    html += '</tr></thead><tbody>';\n\n    items.forEach(function (r) {\n      var sev = r.by_severity || r.severity || {};\n      var total = r.total_findings || r.total || 0;\n      html += '<tr>';\n      html += '<td style="white-space:nowrap;">' + (r.run_id || "–") + '</td>';\n      html += '<td>' + total + '</td>';\n      html += '<td>' + (sev.CRITICAL || 0) + '</td>';\n      html += '<td>' + (sev.HIGH || 0) + '</td>';\n      html += '<td>' + (sev.MEDIUM || 0) + '</td>';\n      html += '<td>' + (sev.LOW || 0) + '</td>';\n      html += '</tr>';\n    });\n\n    html += '</tbody></table></div>';\n    container.innerHTML = html;\n  }\n\n  function loadRuns() {\n    fetch("/api/vsp/runs_index_v3_v3", { cache: "no-store" })\n      .then(function (res) { return res.json(); })\n      .then(function (data) { renderRuns(data); })\n      .catch(function (err) {\n        console.error("[VSP] load runs_index_v3 error:", err);\n        var container = document.getElementById("vsp-runs-container");\n        if (container) {\n          container.innerHTML =\n            '<p style="font-size:12px;color:#fca5a5;">Lỗi khi tải dữ liệu runs.</p>';\n        }\n      });\n  }\n\n  /* ======================\n   *  DATA SOURCE (TAB 3)\n   * ====================== */\n  function get(obj, key) {\n    return obj && obj[key] != null ? obj[key] : 0;\n  }\n\n  function renderDatasource(data) {\n    var container = document.getElementById("vsp-datasource-container");\n    if (!container) return;\n\n    var summary = (data && data.summary) ? data.summary : data || {};\n    var bySev = summary.by_severity || summary.severity || {};\n    var byTool = summary.by_tool || {};\n\n    var html = '';\n    html += '<div class="vsp-card-soft">';\n    html += '<div style="display:grid;grid-template-columns:minmax(0,0.7fr) minmax(0,1fr);gap:8px;">';\n\n    // Bảng theo severity\n    html += '<div>';\n    html += '<div style="font-size:12px;font-weight:600;color:#e5e7eb;margin-bottom:4px;">Tổng quan theo mức độ</div>';\n    html += '<table class="vsp-table" style="font-size:11px;">';\n    html += '<thead><tr><th>Severity</th><th>Count</th></tr></thead><tbody>';\n    ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"].forEach(function (sev) {\n      html += '<tr>';\n      html += '<td>' + sev + '</td>';\n      html += '<td>' + get(bySev, sev) + '</td>';\n      html += '</tr>';\n    });\n    html += '</tbody></table>';\n    html += '</div>';\n\n    // Bảng theo tool\n    html += '<div>';\n    html += '<div style="font-size:12px;font-weight:600;color:#e5e7eb;margin-bottom:4px;">Theo tool</div>';\n\n    var toolNames = Object.keys(byTool || {});\n    if (!toolNames.length) {\n      html += '<p style="font-size:11px;color:#9ca3c7;">Không có dữ liệu theo tool.</p>';\n    } else {\n      html += '<table class="vsp-table" style="font-size:11px;">';\n      html += '<thead><tr>';\n      html += '<th>Tool</th>';\n      html += '<th>CRI</th>';\n      html += '<th>HIGH</th>';\n      html += '<th>MED</th>';\n      html += '<th>LOW</th>';\n      html += '<th>INFO</th>';\n      html += '<th>TRACE</th>';\n      html += '</tr></thead><tbody>';\n\n      toolNames.forEach(function (tool) {\n        var sev = byTool[tool] || {};\n        html += '<tr>';\n        html += '<td>' + tool + '</td>';\n        html += '<td>' + get(sev,"CRITICAL") + '</td>';\n        html += '<td>' + get(sev,"HIGH") + '</td>';\n        html += '<td>' + get(sev,"MEDIUM") + '</td>';\n        html += '<td>' + get(sev,"LOW") + '</td>';\n        html += '<td>' + get(sev,"INFO") + '</td>';\n        html += '<td>' + get(sev,"TRACE") + '</td>';\n        html += '</tr>';\n      });\n\n      html += '</tbody></table>';\n    }\n\n    html += '</div>'; // col tool\n    html += '</div>'; // grid\n    html += '</div>'; // card-soft\n\n    container.innerHTML = html;\n  }\n\n  function loadDatasource() {\n    fetch("/api/vsp/datasource?mode=dashboard", { cache: "no-store" })\n      .then(function (res) { return res.json(); })\n      .then(function (data) { renderDatasource(data); })\n      .catch(function (err) {\n        console.error("[VSP] load datasource dashboard error:", err);\n        var container = document.getElementById("vsp-datasource-container");\n        if (container) {\n          container.innerHTML =\n            '<p style="font-size:12px;color:#fca5a5;">Lỗi khi tải unified datasource.</p>';\n        }\n      });\n  }\n\n  /* ======================\n   *  INIT\n   * ====================== */\n  function init() {\n    loadRuns();\n    loadDatasource();\n  }\n\n  // Cho chắc chắn chạy sau khi DOM sẵn sàng\n  document.addEventListener("DOMContentLoaded", init);\n  window.VSP_DASHBOARD_COMM_ENHANCE_V1 = init;\n})();\n\n\n/* ==== END static/js/vsp_dashboard_comm_enhance_v1.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_dashboard_enhance_p0_clean_v1.js ==== */\n\n// VSP_SAFE_DRILLDOWN_HARDEN_P0_V6\n/* VSP_DASHBOARD_ENHANCE_P0_CLEAN_V1\n * P0 goal: NO red console errors, no drilldown symbol usage, safe degrade.\n */\n(function(){\n  'use strict';\n\n  \n\n\n\n\n\n/* VSP_FIX_DRILLDOWN_CALLSITE_P0_V5: safe-call drilldown artifacts (function OR object.open) */\nfunction __VSP_DD_ART_CALL__(h, ...args) {\n  try {\n    if (typeof h === 'function') return h(...args);\n    if (h && typeof h.open === 'function') return h.open(...args);\n  } catch(e) { try{console.warn('[VSP][DD_SAFE]', e);}catch(_e){} }\n  return null;\n}\n\n/* VSP_FIX_DRILLDOWN_CALLSITE_P0_V3: safe-call for drilldown artifacts (function OR object.open) */\nfunction __VSP_DD_ART_CALL__(h, ...args) {\n  try {\n    if (typeof h === 'function') return h(...args);\n    if (h && typeof h.open === 'function') return h.open(...args);\n  } catch (e) {\n    try { console.warn('[VSP][DD_SAFE] call failed', e); } catch (_e) {}\n  }\n  return null;\n}\n\n/* VSP_FIX_DRILLDOWN_ARTIFACTS_NOT_FUNCTION_P0_V2\n * Fix: TypeError __VSP_DD_ART_CALL__(VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2, ...) is not a function\n * Normalize BEFORE first use:\n *   - if function: keep\n *   - if object with .open(): wrap as function(arg)->obj.open(arg)\n *   - else: no-op (never throw)\n */\n(function(){\n  'use strict';\n  if (window.__VSP_FIX_DRILLDOWN_ARTIFACTS_NOT_FUNCTION_P0_V2) return;\n  window.__VSP_FIX_DRILLDOWN_ARTIFACTS_NOT_FUNCTION_P0_V2 = 1;\n\n  function normalize(v){\n    if (typeof v === 'function') return v;\n    if (v && typeof v.open === 'function') {\n      const obj = v;\n      const fn = function(arg){ try { return obj.open(arg); } catch(e){ console.warn('[VSP][DD_FIX] open() failed', e); return null; } };\n      fn.__wrapped_from_object = true;\n      return fn;\n    }\n    const noop = function(_arg){ return null; };\n    noop.__noop = true;\n    return noop;\n  }\n\n  try {\n    // trap future assignments\n    let _val = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;\n    Object.defineProperty(window, 'VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2', {\n      configurable: true, enumerable: true,\n      get: function(){ return _val; },\n      set: function(v){ _val = normalize(v); }\n    });\n    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = _val;\n  } catch(e) {\n    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = normalize(window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2);\n  }\n})();\n\nconst TAG = '[VSP_DASH_P0_CLEAN]';\n\n  function $(sel, root){ try{ return (root||document).querySelector(sel); }catch(_){ return null; } }\n  function $all(sel, root){ try{ return Array.from((root||document).querySelectorAll(sel)); }catch(_){ return []; } }\n\n  async function fetchJSON(url, opts){\n    try{\n      const r = await fetch(url, Object.assign({cache:'no-store'}, opts||{}));\n      if(!r.ok) throw new Error('HTTP '+r.status);\n      return await r.json();\n    }catch(e){\n      console.warn(TAG, 'fetch failed', url, e);\n      return null;\n    }\n  }\n\n  function setText(id, txt){\n    const el = document.getElementById(id);\n    if(!el) return;\n    el.textContent = (txt==null?'':String(txt));\n  }\n\n  function safeInit(){\n    // Do NOT reference VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 at all.\n    // Only do harmless hydration.\n    console.log(TAG, 'loaded');\n\n    // 1) Try read dashboard data (best effort)\n    fetchJSON('/api/vsp/dashboard_v3').then(d=>{\n      if(!d){ return; }\n      try{\n        // If your template has any of these ids, fill them. If not, no-op.\n        if (d.by_severity && typeof d.by_severity === 'object'){\n          setText('kpi-total', d.by_severity.TOTAL ?? d.total ?? '');\n          setText('kpi-critical', d.by_severity.CRITICAL ?? '');\n          setText('kpi-high', d.by_severity.HIGH ?? '');\n          setText('kpi-medium', d.by_severity.MEDIUM ?? '');\n          setText('kpi-low', d.by_severity.LOW ?? '');\n          setText('kpi-info', d.by_severity.INFO ?? '');\n          setText('kpi-trace', d.by_severity.TRACE ?? '');\n        }\n      }catch(e){\n        console.warn(TAG, 'render kpi failed', e);\n      }\n    });\n\n    // 2) Gate: keep whatever other modules do; we just avoid crashing.\n    // If you want, we can add canonical gate wiring later.\n\n    // 3) Charts: do nothing here. Avoid bootstrap retry spam.\n  }\n\n  if (document.readyState === 'loading'){\n    document.addEventListener('DOMContentLoaded', safeInit, {once:true});\n  }else{\n    safeInit();\n  }\n})();\n\n\n/* ==== END static/js/vsp_dashboard_enhance_p0_clean_v1.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_dashboard_extras_v2.js ==== */\n\n// ======================= VSP_DASHBOARD_EXTRAS_V2 =======================\n// Dò table theo header thay vì ID:\n//  - Top risk findings  : headers ~ [Severity, Tool, Location, Rule]\n//  - Top noisy paths    : headers ~ [Path, Total, Noise level]\n\n(function () {\n  console.log("[EXTRAS] script loaded (header-scan mode)");\n\n  function norm(str) {\n    return (str || "").trim().toLowerCase();\n  }\n\n  function getHeaders(table) {\n    const ths = table.querySelectorAll("thead tr th");\n    if (!ths.length) return [];\n    return Array.prototype.map.call(ths, (th) => norm(th.textContent));\n  }\n\n  function findTableByHeaders(expected) {\n    const tables = document.querySelectorAll("table");\n    for (const tbl of tables) {\n      const heads = getHeaders(tbl);\n      if (heads.length < expected.length) continue;\n      let ok = true;\n      for (let i = 0; i < expected.length; i++) {\n        if (!heads[i] || heads[i].indexOf(expected[i]) === -1) {\n          ok = false;\n          break;\n        }\n      }\n      if (ok) return tbl;\n    }\n    return null;\n  }\n\n  function renderTopRisk(list) {\n    const tbl = findTableByHeaders(["severity", "tool", "location", "rule"]);\n    if (!tbl) {\n      console.warn("[EXTRAS] Không tìm thấy table top risk theo header");\n      return;\n    }\n    const tbody = tbl.querySelector("tbody") || tbl;\n    tbody.innerHTML = "";\n\n    if (!list || list.length === 0) {\n      const tr = document.createElement("tr");\n      const td = document.createElement("td");\n      td.colSpan = 4;\n      td.textContent = "No critical/high findings in this run.";\n      td.classList.add("vsp-empty-cell");\n      tr.appendChild(td);\n      tbody.appendChild(tr);\n      return;\n    }\n\n    list.forEach((item) => {\n      const tr = document.createElement("tr");\n\n      const tdSev = document.createElement("td");\n      tdSev.textContent = item.severity || "-";\n      tdSev.classList.add("vsp-sev", "vsp-sev-" + (item.severity || "").toLowerCase());\n\n      const tdTool = document.createElement("td");\n      tdTool.textContent = item.tool || "-";\n\n      const tdLoc = document.createElement("td");\n      tdLoc.textContent = item.location || "-";\n\n      const tdRule = document.createElement("td");\n      tdRule.textContent = item.rule_id || item.cwe || "-";\n\n      tr.appendChild(tdSev);\n      tr.appendChild(tdTool);\n      tr.appendChild(tdLoc);\n      tr.appendChild(tdRule);\n\n      tbody.appendChild(tr);\n    });\n  }\n\n  function renderTopNoisy(list) {\n    const tbl = findTableByHeaders(["path", "total", "noise"]);\n    if (!tbl) {\n      console.warn("[EXTRAS] Không tìm thấy table top noisy theo header");\n      return;\n    }\n    const tbody = tbl.querySelector("tbody") || tbl;\n    tbody.innerHTML = "";\n\n    if (!list || list.length === 0) {\n      const tr = document.createElement("tr");\n      const td = document.createElement("td");\n      td.colSpan = 3;\n      td.textContent = "No medium/low/info/trace clusters in this run.";\n      td.classList.add("vsp-empty-cell");\n      tr.appendChild(td);\n      tbody.appendChild(tr);\n      return;\n    }\n\n    list.forEach((item) => {\n      const tr = document.createElement("tr");\n\n      const tdPath = document.createElement("td");\n      tdPath.textContent = item.path || "-";\n\n      const tdTotal = document.createElement("td");\n      tdTotal.textContent = item.total != null ? String(item.total) : "-";\n\n      const tdNoise = document.createElement("td");\n      tdNoise.textContent = item.noise_level || "-";\n      tdNoise.classList.add("vsp-noise-" + (item.noise_level || "").toLowerCase());\n\n      tr.appendChild(tdPath);\n      tr.appendChild(tdTotal);\n      tr.appendChild(tdNoise);\n\n      tbody.appendChild(tr);\n    });\n  }\n\n  async function init() {\n    try {\n      const res = await fetch("/static/data/vsp_dashboard_extras_latest.json", {\n        cache: "no-store",\n      });\n      console.log("[EXTRAS] fetch status", res.status);\n      if (!res.ok) {\n        console.warn("[EXTRAS] Không load được extras JSON:", res.status);\n        return;\n      }\n      const data = await res.json();\n      console.log("[EXTRAS] Loaded extras for run", data.run_id);\n\n      renderTopRisk(data.top_risk_findings || []);\n      renderTopNoisy(data.top_noisy_paths || []);\n    } catch (err) {\n      console.error("[EXTRAS][ERR] Khi load extras:", err);\n    }\n  }\n\n  document.addEventListener("DOMContentLoaded", init);\n})();\n\n\n/* ==== END static/js/vsp_dashboard_extras_v2.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_dashboard_findings_v1.js ==== */\n\n;(function () {\n  const LOG_PREFIX = "[VSP_DASH_FINDINGS]";\n  console.log(LOG_PREFIX, "Stub loaded – Dashboard findings zone is disabled in this build.");\n  // Bản thương mại V1: không inject extra findings zone để giữ layout gọn.\n  // Khi nào muốn bật lại, sẽ viết lại file này theo spec mới.\n})();\n\n\n/* ==== END static/js/vsp_dashboard_findings_v1.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_dashboard_kpi_adv_v1.js ==== */\n\n(function () {\n  'use strict';\n\n  const API_URL = '/api/vsp/dashboard_v3_v2';\n\n  function findKpiCardByTitle(titleText) {\n    var all = document.querySelectorAll('*');\n    var titleEl = null;\n\n    for (var i = 0; i < all.length; i++) {\n      var txt = (all[i].textContent || '').trim();\n      if (txt === titleText) {\n        titleEl = all[i];\n        break;\n      }\n    }\n    if (!titleEl) return null;\n\n    var card = titleEl;\n    for (var depth = 0; depth < 5 && card; depth++) {\n      if (card.classList && card.classList.contains('vsp-kpi-card')) {\n        return card;\n      }\n      card = card.parentElement;\n    }\n    return titleEl.parentElement || titleEl;\n  }\n\n  function setKpiValue(title, main, sub) {\n    var card = findKpiCardByTitle(title);\n    if (!card) return;\n\n    var mainEl = card.querySelector('.vsp-kpi-value');\n    if (!mainEl) {\n      mainEl = document.createElement('div');\n      mainEl.className = 'vsp-kpi-value';\n      card.appendChild(mainEl);\n    }\n    mainEl.textContent = main;\n\n    if (sub !== undefined) {\n      var subEl = card.querySelector('.vsp-kpi-sub');\n      if (!subEl) {\n        subEl = document.createElement('div');\n        subEl.className = 'vsp-kpi-sub';\n        card.appendChild(subEl);\n      }\n      subEl.textContent = sub;\n    }\n  }\n\n  function renderKpi(data) {\n    if (!data) return;\n\n    var total = Number(data.total_findings || 0);\n\n    var summary = data.summary || {};\n    var sev = summary.by_severity || data.severity || {};\n\n    var crit  = Number(sev.CRITICAL || 0);\n    var high  = Number(sev.HIGH     || 0);\n    var med   = Number(sev.MEDIUM   || 0);\n    var low   = Number(sev.LOW      || 0);\n    var info  = Number(sev.INFO     || 0);\n    var trace = Number(sev.TRACE    || 0);\n    var infoTrace = info + trace;\n\n    // 6 KPI severity\n    setKpiValue('Total Findings', total.toLocaleString(), '');\n    setKpiValue('Critical',       crit.toLocaleString(), '');\n    setKpiValue('High',           high.toLocaleString(), '');\n    setKpiValue('Medium',         med.toLocaleString(), '');\n    setKpiValue('Low',            low.toLocaleString(), '');\n    setKpiValue('Info / Trace',   infoTrace.toLocaleString(), '');\n\n    // 4 KPI nâng cao – hiện BE chưa có, để "-" cho đẹp\n    var score   = summary.security_score;\n    var topTool = summary.top_risky_tool || '-';\n    var topCwe  = summary.top_cwe        || '-';\n    var topMod  = summary.top_module     || '-';\n\n    if (typeof score === 'number') {\n      setKpiValue('Security Score', String(score), '/100');\n    } else {\n      setKpiValue('Security Score', '-', '/100');\n    }\n\n    setKpiValue('Top Risky Tool', topTool, '');\n    setKpiValue('Top CWE',        topCwe,  '');\n    setKpiValue('Top Module',     topMod,  '');\n  }\n\n  function loadKpi() {\n    fetch(API_URL)\n      .then(function (r) { return r.json(); })\n      .then(function (data) {\n        if (!data || data.ok === false) {\n          console.warn('[VSP][KPI] /api/vsp/dashboard_v3_v2 not ok:', data);\n          return;\n        }\n        renderKpi(data);\n      })\n      .catch(function (err) {\n        console.error('[VSP][KPI] fetch error:', err);\n      });\n  }\n\n  document.addEventListener('DOMContentLoaded', loadKpi);\n})();\n\n\n/* ==== END static/js/vsp_dashboard_kpi_adv_v1.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_dashboard_kpi_adv_v2.js ==== */\n\n/* ---------------------------------------------------------\n * VSP CIO VIEW – Advanced KPI (Top risks + Noisy paths)\n * Không sửa layout, chỉ inject data vào 2 bảng:\n *  - "Top risk findings"\n *  - "Top noisy paths"\n * Tự tìm bảng bằng heading text, không cần thêm id.\n * --------------------------------------------------------- */\n\n(function () {\n  "use strict";\n\n  function dbg() {\n    if (window.console && console.log) {\n      console.log.apply(console, arguments);\n    }\n  }\n\n  function findTbodyByHeading(keyword) {\n    keyword = (keyword || "").toLowerCase();\n    if (!keyword) return null;\n\n    var headings = document.querySelectorAll("h2, h3, h4, h5");\n    for (var i = 0; i < headings.length; i++) {\n      var h = headings[i];\n      var txt = (h.textContent || "").toLowerCase();\n      if (txt.indexOf(keyword) !== -1) {\n        // tìm container gần nhất có table\n        var container = h.closest("section, article, div") || h.parentElement;\n        if (!container) continue;\n        var tbody = container.querySelector("tbody");\n        if (tbody) {\n          return tbody;\n        }\n      }\n    }\n    return null;\n  }\n\n  /* ------------------------------\n     TOP RISK FINDINGS\n     (CRITICAL + HIGH)\n  ------------------------------ */\n  function loadTopRiskFindings() {\n    var severities = ["CRITICAL", "HIGH"];\n    var promises = [];\n\n    for (var i = 0; i < severities.length; i++) {\n      (function (sev) {\n        var url = "/api/vsp/datasource_v2?severity=" +\n                  encodeURIComponent(sev) + "&limit=50";\n        dbg("[VSP][ADV] top risks GET", url);\n        var p = fetch(url)\n          .then(function (r) { return r.json(); })\n          .catch(function (e) {\n            console.error("[VSP][ADV] top risks fetch ERR (" + sev + "):", e);\n            return null;\n          });\n        promises.push(p);\n      })(severities[i]);\n    }\n\n    Promise.all(promises).then(function (results) {\n      var tbody = findTbodyByHeading("top risk findings");\n      if (!tbody) {\n        dbg("[VSP][ADV] Không tìm thấy bảng 'Top risk findings' trong DOM.");\n        return;\n      }\n\n      var allItems = [];\n      for (var i = 0; i < results.length; i++) {\n        var res = results[i];\n        if (!res || res.ok === false || !Array.isArray(res.items)) continue;\n        allItems = allItems.concat(res.items);\n      }\n\n      if (!allItems.length) {\n        tbody.innerHTML =\n          '<tr><td colspan="4">No CRITICAL/HIGH findings.</td></tr>';\n        return;\n      }\n\n      // sort: CRITICAL trước HIGH\n      var weight = { CRITICAL: 2, HIGH: 1 };\n      allItems.sort(function (a, b) {\n        var sa = a.severity_effective || a.severity || "HIGH";\n        var sb = b.severity_effective || b.severity || "HIGH";\n        var wa = weight[sa] || 0;\n        var wb = weight[sb] || 0;\n        if (wa !== wb) return wb - wa;\n        return 0;\n      });\n\n      // Lấy TOP 10\n      allItems = allItems.slice(0, 10);\n\n      tbody.innerHTML = "";\n      for (var j = 0; j < allItems.length; j++) {\n        var it = allItems[j];\n        var sev  = it.severity_effective || it.severity || "N/A";\n        var tool = it.tool || "";\n        var loc  = it.file || it.path || "";\n        var rule = it.rule_id || it.cwe || "";\n\n        var tr = document.createElement("tr");\n        tr.innerHTML =\n          "<td>" + sev  + "</td>" +\n          "<td>" + tool + "</td>" +\n          "<td>" + loc  + "</td>" +\n          "<td>" + rule + "</td>";\n        tbody.appendChild(tr);\n      }\n    });\n  }\n\n  /* ------------------------------\n     TOP NOISY PATHS\n     (MEDIUM / LOW / INFO / TRACE)\n  ------------------------------ */\n  function loadTopNoisyPaths() {\n    var severities = ["MEDIUM", "LOW", "INFO", "TRACE"];\n    var promises = [];\n\n    for (var i = 0; i < severities.length; i++) {\n      (function (sev) {\n        var url = "/api/vsp/datasource_v2?severity=" +\n                  encodeURIComponent(sev) + "&limit=200";\n        dbg("[VSP][ADV] noisy paths GET", url);\n        var p = fetch(url)\n          .then(function (r) { return r.json(); })\n          .catch(function (e) {\n            console.error("[VSP][ADV] noisy paths fetch ERR (" + sev + "):", e);\n            return null;\n          });\n        promises.push(p);\n      })(severities[i]);\n    }\n\n    Promise.all(promises).then(function (results) {\n      var tbody = findTbodyByHeading("top noisy paths");\n      if (!tbody) {\n        dbg("[VSP][ADV] Không tìm thấy bảng 'Top noisy paths' trong DOM.");\n        return;\n      }\n\n      var counts = {}; // path/file -> total\n\n      for (var i = 0; i < results.length; i++) {\n        var res = results[i];\n        if (!res || res.ok === false || !Array.isArray(res.items)) continue;\n\n        for (var j = 0; j < res.items.length; j++) {\n          var it = res.items[j];\n          var key = it.file || it.path || "";\n          if (!key) continue;\n          if (!counts[key]) counts[key] = 0;\n          counts[key] += 1;\n        }\n      }\n\n      var paths = [];\n      for (var k in counts) {\n        if (!counts.hasOwnProperty(k)) continue;\n        paths.push({ path: k, total: counts[k] });\n      }\n\n      if (!paths.length) {\n        tbody.innerHTML =\n          '<tr><td colspan="3">No noisy paths (MEDIUM/LOW/INFO/TRACE).</td></tr>';\n        return;\n      }\n\n      // sort desc theo total\n      paths.sort(function (a, b) {\n        return b.total - a.total;\n      });\n\n      // helper noise level\n      function noiseLevel(total) {\n        if (total >= 20) return "HIGH";\n        if (total >= 10) return "MEDIUM";\n        if (total >= 3)  return "LOW";\n        return "MINOR";\n      }\n\n      // Lấy TOP 10\n      paths = paths.slice(0, 10);\n\n      tbody.innerHTML = "";\n      for (var p = 0; p < paths.length; p++) {\n        var e = paths[p];\n        var tr = document.createElement("tr");\n        tr.innerHTML =\n          "<td>" + e.path + "</td>" +\n          "<td>" + e.total + "</td>" +\n          "<td>" + noiseLevel(e.total) + "</td>";\n        tbody.appendChild(tr);\n      }\n    });\n  }\n\n  /* ------------------------------\n     INIT – KHÔNG ĐỤNG JS CŨ\n  ------------------------------ */\n  function initAdvKpi() {\n    dbg("[VSP][ADV] init advanced KPI (top risks + noisy paths)");\n    loadTopRiskFindings();\n    loadTopNoisyPaths();\n  }\n\n  document.addEventListener("DOMContentLoaded", initAdvKpi);\n})();\n\n\n/* ==== END static/js/vsp_dashboard_kpi_adv_v2.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_dashboard_kpi_force_any_v1.js ==== */\n\n(function () {\n  if (window.VSP_DASH_FORCE_INIT) {\n    console.log('[VSP_DASH_FORCE] already initialized, skip');\n    return;\n  }\n  window.VSP_DASH_FORCE_INIT = true;\n\n  console.log('[VSP_DASH_FORCE] vsp_dashboard_kpi_force_any_v1.js loaded');\n\n  function fmtInt(n) {\n    if (n == null || isNaN(n)) return '--';\n    return Number(n).toLocaleString('en-US');\n  }\n\n  function setText(id, value, isNumber) {\n    var el = document.getElementById(id);\n    if (!el) return;\n    if (value == null || value === '') {\n      el.textContent = '--';\n      return;\n    }\n    el.textContent = isNumber ? fmtInt(value) : String(value);\n  }\n\n  async function loadKpiOnce() {\n    try {\n      const res = await fetch('/api/vsp/dashboard_v3');\n      if (!res.ok) {\n        console.warn('[VSP_DASH_FORCE] dashboard_v3 HTTP != 200', res.status);\n        return;\n      }\n      const data = await res.json();\n      const sev = data.by_severity || data.severity_cards || {};\n\n      let topTool   = data.top_risky_tool;\n      let topCwe    = data.top_impacted_cwe;\n      let topModule = data.top_vulnerable_module;\n\n      if (topCwe && typeof topCwe === 'object') {\n        topCwe =\n          topCwe.cwe_id ||\n          topCwe.cwe ||\n          topCwe.id ||\n          topCwe.name ||\n          JSON.stringify(topCwe);\n      }\n      if (topModule && typeof topModule === 'object') {\n        topModule =\n          topModule.path ||\n          topModule.module ||\n          topModule.id ||\n          topModule.name ||\n          JSON.stringify(topModule);\n      }\n\n      // 5 KPI chính\n      setText('vsp-kpi-total-findings', data.total_findings, true);\n      setText('vsp-kpi-score',          data.security_posture_score, true);\n      setText('vsp-kpi-top-tool',       topTool, false);\n      setText('vsp-kpi-top-cwe',        topCwe, false);\n      setText('vsp-kpi-top-module',     topModule, false);\n\n      // 6 severity\n      setText('vsp-kpi-sev-critical', sev.CRITICAL || 0, true);\n      setText('vsp-kpi-sev-high',     sev.HIGH     || 0, true);\n      setText('vsp-kpi-sev-medium',   sev.MEDIUM   || 0, true);\n      setText('vsp-kpi-sev-low',      sev.LOW      || 0, true);\n      setText('vsp-kpi-sev-info',     sev.INFO     || 0, true);\n      setText('vsp-kpi-sev-trace',    sev.TRACE    || 0, true);\n\n      console.log('[VSP_DASH_FORCE] KPI applied', {\n        total: data.total_findings,\n        score: data.security_posture_score,\n        topTool, topCwe, topModule,\n        by_severity: sev\n      });\n    } catch (e) {\n      console.error('[VSP_DASH_FORCE] Error loading KPI', e);\n    }\n  }\n\n  function init() {\n    var tries = 0;\n    var t = setInterval(function () {\n      var pane = document.getElementById('vsp-dashboard-main');\n      if (pane) {\n        clearInterval(t);\n        loadKpiOnce();\n      } else if (tries++ > 20) {\n        clearInterval(t);\n        console.warn('[VSP_DASH_FORCE] Hết retries, không thấy #vsp-dashboard-main');\n      }\n    }, 500);\n  }\n\n  if (document.readyState === 'complete' || document.readyState === 'interactive') {\n    init();\n  } else {\n    document.addEventListener('DOMContentLoaded', init);\n  }\n})();\n\n\n/* ==== END static/js/vsp_dashboard_kpi_force_any_v1.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_dashboard_kpi_force_any_v2.js ==== */\n\n(function () {\n  console.log('[VSP_DASH_FORCE] vsp_dashboard_kpi_force_any_v2.js loaded');\n\n  function fmtInt(n) {\n    if (n == null || isNaN(n)) return '--';\n    return Number(n).toLocaleString('en-US');\n  }\n\n  function setText(id, value, isNumber) {\n    var el = document.getElementById(id);\n    if (!el) return;\n    if (value == null || value === '') {\n      el.textContent = '--';\n      return;\n    }\n    el.textContent = isNumber ? fmtInt(value) : String(value);\n  }\n\n  async function loadKpiOnce() {\n    try {\n      const res = await fetch('/api/vsp/dashboard_v3');\n      if (!res.ok) {\n        console.warn('[VSP_DASH_FORCE] dashboard_v3 HTTP != 200', res.status);\n        return;\n      }\n      const data = await res.json();\n      const sev = data.by_severity || {};\n\n      let topTool   = data.top_risky_tool;\n      let topCwe    = data.top_impacted_cwe;\n      let topModule = data.top_vulnerable_module;\n\n      if (topCwe && typeof topCwe === 'object') {\n        topCwe = topCwe.cwe_id || topCwe.cwe || topCwe.id || topCwe.name || JSON.stringify(topCwe);\n      }\n      if (topModule && typeof topModule === 'object') {\n        topModule = topModule.path || topModule.module || topModule.id || topModule.name || JSON.stringify(topModule);\n      }\n\n      // 5 KPI chính\n      setText('vsp-kpi-total-findings', data.total_findings, true);\n      setText('vsp-kpi-score',          data.security_posture_score, true);\n      setText('vsp-kpi-top-tool',       topTool, false);\n      setText('vsp-kpi-top-cwe',        topCwe, false);\n      setText('vsp-kpi-top-module',     topModule, false);\n\n      // 6 severity\n      setText('vsp-kpi-sev-critical', sev.CRITICAL || 0, true);\n      setText('vsp-kpi-sev-high',     sev.HIGH     || 0, true);\n      setText('vsp-kpi-sev-medium',   sev.MEDIUM   || 0, true);\n      setText('vsp-kpi-sev-low',      sev.LOW      || 0, true);\n      setText('vsp-kpi-sev-info',     sev.INFO     || 0, true);\n      setText('vsp-kpi-sev-trace',    sev.TRACE    || 0, true);\n\n      console.log('[VSP_DASH_FORCE] KPI applied', {\n        total: data.total_findings,\n        score: data.security_posture_score,\n        topTool, topCwe, topModule,\n        by_severity: sev\n      });\n    } catch (e) {\n      console.error('[VSP_DASH_FORCE] Error loading KPI', e);\n    }\n  }\n\n  function init() {\n    // chỉ chạy khi pane dashboard đã inject\n    var tries = 0;\n    var t = setInterval(function () {\n      var pane = document.getElementById('vsp-dashboard-main');\n      if (pane) {\n        clearInterval(t);\n        loadKpiOnce();\n      } else if (tries++ > 20) {\n        clearInterval(t);\n        console.warn('[VSP_DASH_FORCE] Hết retries, không thấy #vsp-dashboard-main');\n      }\n    }, 500);\n  }\n\n  if (document.readyState === 'complete' || document.readyState === 'interactive') {\n    init();\n  } else {\n    document.addEventListener('DOMContentLoaded', init);\n  }\n})();\n\n\n/* ==== END static/js/vsp_dashboard_kpi_force_any_v2.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_dashboard_kpi_force_any_v3.js ==== */\n\n(function () {\n  if (window.VSP_DASH_FORCE_V3_INIT) {\n    console.log('[VSP_DASH_FORCE] already initialized, skip');\n    return;\n  }\n  window.VSP_DASH_FORCE_V3_INIT = true;\n\n  console.log('[VSP_DASH_FORCE] vsp_dashboard_kpi_force_any_v3.js loaded');\n\n  function fmtInt(n) {\n    if (n == null || isNaN(n)) return '--';\n    return Number(n).toLocaleString('en-US');\n  }\n\n  function setText(id, value, isNumber) {\n    var el = document.getElementById(id);\n    if (!el) return;\n    if (value == null || value === '') {\n      el.textContent = '--';\n      return;\n    }\n    el.textContent = isNumber ? fmtInt(value) : String(value);\n  }\n\n  async function loadKpiOnce() {\n    try {\n      const res = await fetch('/api/vsp/dashboard_v3');\n      if (!res.ok) {\n        console.warn('[VSP_DASH_FORCE] dashboard_v3 HTTP != 200', res.status);\n        return;\n      }\n      const data = await res.json();\n      const sev = data.by_severity || data.severity_cards || {};\n\n      let topTool   = data.top_risky_tool;\n      let topCwe    = data.top_impacted_cwe;\n      let topModule = data.top_vulnerable_module;\n\n      if (topCwe && typeof topCwe === 'object') {\n        topCwe =\n          topCwe.cwe_id ||\n          topCwe.cwe ||\n          topCwe.id ||\n          topCwe.name ||\n          JSON.stringify(topCwe);\n      }\n      if (topModule && typeof topModule === 'object') {\n        topModule =\n          topModule.path ||\n          topModule.module ||\n          topModule.id ||\n          topModule.name ||\n          JSON.stringify(topModule);\n      }\n\n      // 5 KPI chính – ĐÚNG ID HTML ANH ĐANG CÓ\n      setText('vsp-kpi-total',          data.total_findings, true);\n      setText('vsp-kpi-security-score', data.security_posture_score, true);\n      setText('vsp-kpi-top-tool',       topTool, false);\n      setText('vsp-kpi-top-cwe',        topCwe, false);\n      setText('vsp-kpi-top-module',     topModule, false);\n\n      // 6 severity – ĐÚNG ID HTML\n      setText('vsp-kpi-critical', sev.CRITICAL || 0, true);\n      setText('vsp-kpi-high',     sev.HIGH     || 0, true);\n      setText('vsp-kpi-medium',   sev.MEDIUM   || 0, true);\n      setText('vsp-kpi-low',      sev.LOW      || 0, true);\n      setText('vsp-kpi-info',     sev.INFO     || 0, true);\n      setText('vsp-kpi-trace',    sev.TRACE    || 0, true);\n\n      console.log('[VSP_DASH_FORCE] KPI applied', {\n        total: data.total_findings,\n        score: data.security_posture_score,\n        topTool,\n        topCwe,\n        topModule,\n        by_severity: sev\n      });\n    } catch (e) {\n      console.error('[VSP_DASH_FORCE] Error loading KPI', e);\n    }\n  }\n\n  function init() {\n    var tries = 0;\n    var t = setInterval(function () {\n      var pane = document.getElementById('vsp-dashboard-main');\n      if (pane) {\n        clearInterval(t);\n        loadKpiOnce();\n      } else if (tries++ > 20) {\n        clearInterval(t);\n        console.warn('[VSP_DASH_FORCE] Hết retries, không thấy #vsp-dashboard-main');\n      }\n    }, 500);\n  }\n\n  if (document.readyState === 'complete' || document.readyState === 'interactive') {\n    init();\n  } else {\n    document.addEventListener('DOMContentLoaded', init);\n  }\n})();\n\n\n/* ==== END static/js/vsp_dashboard_kpi_force_any_v3.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_dashboard_kpi_v1.js ==== */\n\n\nfunction vspNormalizeTopModule(m) {\n  if (!m) return 'N/A';\n  if (typeof m === 'string') return m;\n  try {\n    if (m.label) return String(m.label);\n    if (m.path) return String(m.path);\n    if (m.id)   return String(m.id);\n    return String(m);\n  } catch (e) {\n    return 'N/A';\n  }\n}\n\n'use strict';\n\n(function () {\n  const LOG = '[VSP_DASHBOARD_KPI]';\n\n  function setText(id, value) {\n    const el = document.getElementById(id);\n    if (!el) return;\n    el.textContent = value;\n  }\n\n  function renderKpi(model) {\n    if (!model) return;\n    const sev =\n      model.severity_cards ||\n      model.summary_by_severity ||\n      model.summary_all ||\n      {};\n\n    const total =\n      model.total_findings ??\n      model.total ??\n      sev.TOTAL ??\n      0;\n\n    setText('vsp-kpi-total', total);\n    setText('vsp-kpi-critical', sev.CRITICAL ?? 0);\n    setText('vsp-kpi-high', sev.HIGH ?? 0);\n    setText('vsp-kpi-medium', sev.MEDIUM ?? 0);\n    setText('vsp-kpi-low', sev.LOW ?? 0);\n    setText('vsp-kpi-info', (sev.INFO ?? 0) + (sev.TRACE ?? 0));\n\n    if (model.security_posture_score != null) {\n      setText('vsp-kpi-score-main', model.security_posture_score + '/100');\n    }\n\n    if (model.top_risky_tool) {\n      setText('vsp-kpi-top-tool', model.top_risky_tool);\n    }\n    if (model.top_impacted_cwe) {\n      setText('vsp-kpi-top-cwe', model.top_impacted_cwe);\n    }\n    if (model.top_vulnerable_module) {\n      setText('vsp-kpi-top-module', model.top_vulnerable_module);\n    }\n\n    if (model.latest_run_id) {\n      setText('vsp-last-run-span', model.latest_run_id);\n    }\n\n    // Cho Charts JS dùng chung model này\n    window.VSP_DASHBOARD_MODEL = model;\n    if (typeof window.vspRenderChartsFromDashboard === 'function') {\n      try {\n        window.vspRenderChartsFromDashboard(model);\n      } catch (e) {\n        console.error(LOG, 'Chart render error', e);\n      }\n    }\n  }\n\n  async function loadDashboard() {\n    const url = '/api/vsp/dashboard_v3';\n    console.log(LOG, 'Loading', url);\n\n    try {\n      const res = await fetch(url, { credentials: 'same-origin' });\n      if (!res.ok) throw new Error('HTTP ' + res.status);\n      const data = await res.json();\n      console.log(LOG, 'Dashboard model:', data);\n      renderKpi(data);\n    } catch (err) {\n      console.error(LOG, 'Load dashboard error:', err);\n      const errBox = document.getElementById('vsp-dashboard-error');\n      if (errBox) {\n        errBox.textContent = 'Không tải được dashboard: ' + (err.message || err);\n        errBox.style.display = 'block';\n      }\n    }\n  }\n\n  document.addEventListener('DOMContentLoaded', loadDashboard);\n})();\n\n\n/* ==== END static/js/vsp_dashboard_kpi_v1.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_dashboard_live_v2.V1_baseline.js ==== */\n\n"use strict";\n\n/**\n * VSP_DASHBOARD_LIVE_V2 – ALL-IN-ONE (datasource + fallback v1/v3)\n */\n\n(function () {\n  const API_SUMMARY      = "/api/vsp/datasource?mode=dashboard";\n  const API_DS_SEV       = (sev, limit) =>\n    "/api/vsp/datasource?severity=" + encodeURIComponent(sev) + "&limit=" + (limit || 1);\n  const API_RUNS_V3      = "/api/vsp/runs_index_v3_v3";\n  const API_RUNS_V1      = "/api/vsp/runs";\n  const API_TREND_V1     = "/api/vsp/trend_v1";\n  const API_SETTINGS     = "/api/vsp/settings/get";\n  const API_OVERRIDES    = "/api/vsp/overrides/list";\n  const API_DASHBOARD_V3 = "/api/vsp/dashboard_v3";\n\n  const SEVERITIES = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "TRACE"];\n\n  function $(id) {\n    return document.getElementById(id);\n  }\n\n  async function fetchJson(url) {\n    const res = await fetch(url, { cache: "no-store" });\n    if (!res.ok) {\n      const err = new Error("HTTP " + res.status + " for " + url);\n      err.status = res.status;\n      throw err;\n    }\n    return await res.json();\n  }\n\n  function safeInt(v) {\n    if (v == null) return 0;\n    const n = Number(v);\n    return Number.isFinite(n) ? n : 0;\n  }\n\n  function escHtml(str) {\n    return String(str)\n      .replace(/&/g, "&amp;")\n      .replace(/</g, "&lt;")\n      .replace(/>/g, "&gt;");\n  }\n\n  function setNoData(container, msg) {\n    if (!container) return;\n    container.innerHTML =\n      '<p style="font-size:12px;color:#9ca3c7;">' + msg + "</p>";\n  }\n\n  /* ========== KPI + DONUT ========== */\n\n  let donutChart = null;\n\n  function renderKpisAndDonut(dash, bySev) {\n    const sev = bySev || {};\n    const fmt = (n) => n.toLocaleString("en-US");\n\n    const crit  = safeInt(sev.CRITICAL);\n    const high  = safeInt(sev.HIGH);\n    const med   = safeInt(sev.MEDIUM);\n    const low   = safeInt(sev.LOW);\n    const info  = safeInt(sev.INFO);\n    const trace = safeInt(sev.TRACE);\n\n    const totalFromSev = crit + high + med + low + info + trace;\n    const total =\n      safeInt(dash.total_findings) ||\n      safeInt(dash.total) ||\n      totalFromSev;\n\n    const elTotal = $("kpi-total-findings");\n    if (elTotal) elTotal.textContent = fmt(total);\n\n    const elCrit = $("kpi-critical");\n    if (elCrit) elCrit.textContent = fmt(crit);\n\n    const elHigh = $("kpi-high");\n    if (elHigh) elHigh.textContent = fmt(high);\n\n    const elMed = $("kpi-medium");\n    if (elMed) elMed.textContent = fmt(med);\n\n    const elLow = $("kpi-low");\n    if (elLow) elLow.textContent = fmt(low);\n\n    const elInfoTrace = $("kpi-info-trace");\n    if (elInfoTrace) elInfoTrace.textContent = fmt(info + trace);\n\n    const lastRunId = $("vsp-last-run-id");\n    if (lastRunId) lastRunId.textContent = dash.run_id || "–";\n\n    const lastRunTs = $("vsp-last-run-ts");\n    if (lastRunTs) {\n      const ts = dash.ts || dash.last_run_ts || dash.last_ts;\n      lastRunTs.textContent = ts ? ts : "Last run: –";\n    }\n\n    // Donut\n    const canvas = $("severity_donut_chart");\n    if (canvas && typeof Chart !== "undefined") {\n      if (donutChart) donutChart.destroy();\n      donutChart = new Chart(canvas, {\n        type: "doughnut",\n        data: {\n          labels: ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "TRACE"],\n          datasets: [\n            {\n              data: [crit, high, med, low, info, trace],\n              backgroundColor: [\n                "#ff4b6a",\n                "#ff9f43",\n                "#ffd166",\n                "#4ade80",\n                "#38bdf8",\n                "#a855f7",\n              ],\n              borderWidth: 0,\n            },\n          ],\n        },\n        options: {\n          responsive: true,\n          maintainAspectRatio: false,\n          cutout: "70%",\n          plugins: { legend: { display: false } },\n        },\n      });\n    }\n\n    // fallback trend 1 điểm, sẽ bị override nếu initTrend() load được nhiều điểm\n    renderTrend([{ label: dash.run_id || "Last run", total }]);\n  }\n\n  async function computeSeverityBucketsFromDatasource() {\n    const buckets = {\n      CRITICAL: 0,\n      HIGH: 0,\n      MEDIUM: 0,\n      LOW: 0,\n      INFO: 0,\n      TRACE: 0,\n    };\n\n    const promises = SEVERITIES.map(async (sev) => {\n      try {\n        const resp = await fetchJson(API_DS_SEV(sev, 1));\n        const total = safeInt(resp.total || resp.total_findings || resp.count);\n        buckets[sev] = total;\n      } catch (err) {\n        console.warn("[VSP] severity", sev, "error:", err);\n      }\n    });\n\n    await Promise.all(promises);\n    return buckets;\n  }\n\n  /* ========== TREND ========== */\n\n  let trendChart = null;\n\n  function renderTrend(points) {\n    const canvas = $("trend_line_chart");\n    if (!canvas || typeof Chart === "undefined") return;\n    if (!Array.isArray(points) || !points.length) return;\n\n    const labels = points.map((p) => p.label || "");\n    const totals = points.map((p) => safeInt(p.total || p.total_findings));\n\n    // Destroy mọi chart đang gắn với canvas này (kể cả không lưu trong trendChart)\n    if (typeof Chart.getChart === "function") {\n      try {\n        const existing = Chart.getChart(canvas);\n        if (existing) existing.destroy();\n      } catch (e) {\n        console.warn("[VSP][TREND] Chart.getChart destroy error:", e);\n      }\n    }\n\n    if (trendChart) {\n      try {\n        trendChart.destroy();\n      } catch (e) {\n        console.warn("[VSP][TREND] trendChart.destroy error:", e);\n      }\n      trendChart = null;\n    }\n\n    trendChart = new Chart(canvas, {\n      type: "line",\n      data: {\n        labels,\n        datasets: [\n          {\n            label: "Total findings",\n            data: totals,\n            tension: 0.35,\n            borderWidth: 2,\n            pointRadius: 3,\n          },\n        ],\n      },\n      options: {\n        responsive: true,\n        maintainAspectRatio: false,\n        plugins: { legend: { display: false } },\n        scales: {\n          x: {\n            ticks: { maxRotation: 45, minRotation: 45 },\n            grid: { display: false },\n          },\n          y: {\n            beginAtZero: true,\n            grid: { color: "rgba(148,163,210,0.25)" },\n          },\n        },\n      },\n    });\n  }\n\n  async function initTrend() {\n    // 1) trend_v1 nếu có\n    try {\n      const t = await fetchJson(API_TREND_V1);\n      const pts = Array.isArray(t.points) ? t.points : [];\n      if (pts.length) {\n        renderTrend(pts);\n        return;\n      }\n    } catch (e) {\n      console.warn("[VSP] trend_v1 error:", e);\n    }\n\n    // 2) runs_index_v3 nếu có\n    try {\n      const runs = await fetchJson(API_RUNS_V3);\n      if (Array.isArray(runs) && runs.length) {\n        const pts = runs\n          .slice(0, 10)\n          .map((r) => ({\n            label: r.run_id || "",\n            total: r.total_findings || r.total || 0,\n          }))\n          .reverse();\n        renderTrend(pts);\n        return;\n      }\n    } catch (e) {\n      console.warn("[VSP] runs_index_v3 error (trend):", e);\n    }\n    // fallback = 1 điểm đã vẽ sẵn bởi renderKpisAndDonut\n  }\n\n      /* ========== TOP CWE BAR ========== */\n\n  let topCweChart = null;\n\n  function ensureTopCweCanvas() {\n    let canvas = $("top_cwe_chart");\n    if (canvas) return canvas;\n\n    const table = document.querySelector("#top-cwe-table");\n    if (table) {\n      table.style.display = "none";\n      const parent = table.parentElement || table.parentNode || table;\n      canvas = document.createElement("canvas");\n      canvas.id = "top_cwe_chart";\n      canvas.style.width = "100%";\n      canvas.style.height = "210px";\n      parent.appendChild(canvas);\n      return canvas;\n    }\n    return null;\n  }\n\n  function renderTopCweBarFromInsights(items) {\n    const canvas = ensureTopCweCanvas();\n    if (!canvas || typeof Chart === "undefined") return;\n\n    const arr = Array.isArray(items) ? items : [];\n    if (!arr.length) {\n      console.debug("[VSP] renderTopCweBarFromInsights: empty items");\n      return;\n    }\n\n    const labels = arr.map((it) => it.cwe || "UNKNOWN");\n    const totals = arr.map((it) => safeInt(it.count || 0));\n\n    if (topCweChart) {\n      topCweChart.destroy();\n    }\n\n    topCweChart = new Chart(canvas, {\n      type: "bar",\n      data: {\n        labels,\n        datasets: [\n          {\n            label: "Findings",\n            data: totals,\n            borderWidth: 1,\n          },\n        ],\n      },\n      options: {\n        responsive: true,\n        maintainAspectRatio: false,\n        plugins: {\n          legend: { display: false },\n          tooltip: {\n            callbacks: {\n              label: (ctx) => {\n                const v = ctx.parsed.y || 0;\n                return `  ${v} findings`;\n              },\n            },\n          },\n        },\n        scales: {\n          x: {\n            grid: { display: false },\n            ticks: { maxRotation: 45, minRotation: 45 },\n          },\n          y: {\n            beginAtZero: true,\n            grid: { color: "rgba(148,163,210,0.25)" },\n          },\n        },\n      },\n    });\n  }\n\n  async function initTopCweFromInsights() {\n    try {\n      const data = await fetchJson(API_TOP_CWE_V1);\n      if (!data || data.ok === false) {\n        console.warn("[VSP] TOPCWE – insights ok=false hoặc data rỗng", data && data.error);\n        return;\n      }\n      const items = Array.isArray(data.items) ? data.items : [];\n      if (!items.length) {\n        console.warn("[VSP] TOPCWE – empty items from insights");\n        return;\n      }\n      renderTopCweBarFromInsights(items);\n    } catch (e) {\n      console.warn("[VSP] TOPCWE – insights fetch error:", e);\n    }\n  }\n\n  // Giữ hàm initTopCwe cũ để loadAll() vẫn gọi được,\n  // nhưng bên trong chỉ còn gọi insights.\n  async function initTopCwe(summary) {  // summary không dùng nữa\n    await initTopCweFromInsights();\n  }\n\n/* ========== TOP FINDINGS ========== */\n\n  async function initTopFindings() {\n    const tbody = document.querySelector("#top-findings-table tbody");\n    if (!tbody) return;\n\n    try {\n      const resp = await fetchJson(API_DS_SEV("CRITICAL", 5));\n      const items = Array.isArray(resp.items) ? resp.items : [];\n      if (!items.length) {\n        tbody.innerHTML =\n          '<tr><td colspan="10" style="color:#9ca3c7;font-size:11px;">Không load được dữ liệu top findings.</td></tr>';\n        return;\n      }\n\n      const rows = items\n        .map((it) => {\n          const sev =\n            '<span class="vsp-severity-badge vsp-severity-critical">CRITICAL</span>';\n          const loc = it.location || it.file || it.path || "";\n          const rule = it.rule || it.rule_id || it.cwe || "";\n          const tool = it.tool || it.source || "";\n          return (\n            "<tr>" +\n            "<td>" + sev + "</td>" +\n            "<td>" + escHtml(loc) + "</td>" +\n            "<td>" + escHtml(rule) + "</td>" +\n            "<td>" + escHtml(tool) + "</td>" +\n            "</tr>"\n          );\n        })\n        .join("");\n\n      tbody.innerHTML = rows;\n    } catch (e) {\n      console.warn("[VSP] initTopFindings error:", e);\n      tbody.innerHTML =\n        '<tr><td colspan="10" style="color:#9ca3c7;font-size:11px;">Không load được dữ liệu top findings.</td></tr>';\n    }\n  }\n\n  /* ========== RUNS TAB ========== */\n\n  function renderRunsTable(runs) {\n    const container = $("vsp-runs-container");\n    if (!container) return;\n\n    if (!Array.isArray(runs) || !runs.length) {\n      setNoData(container, "Không load được dữ liệu runs.");\n      return;\n    }\n\n    const rows = runs\n      .slice(0, 20)\n      .map((r) => {\n        const sev = r.by_severity || r.severity || {};\n        return (\n          "<tr>" +\n          "<td>" + escHtml(r.run_id || r.id || "") + "</td>" +\n          "<td>" + safeInt(r.total_findings || r.total) + "</td>" +\n          "<td>" + safeInt(sev.CRITICAL) + "</td>" +\n          "<td>" + safeInt(sev.HIGH) + "</td>" +\n          "<td>" + safeInt(sev.MEDIUM) + "</td>" +\n          "<td>" + safeInt(sev.LOW) + "</td>" +\n          "</tr>"\n        );\n      })\n      .join("");\n\n    container.innerHTML =\n      '<table class="vsp-table">' +\n      "<thead><tr>" +\n      "<th>Run ID</th>" +\n      "<th>Total</th>" +\n      "<th>CRI</th>" +\n      "<th>HIGH</th>" +\n      "<th>MED</th>" +\n      "<th>LOW</th>" +\n      "</tr></thead>" +\n      "<tbody>" + rows + "</tbody></table>";\n  }\n\n  async function initRunsTab() {\n    const container = $("vsp-runs-container");\n    if (!container) return;\n\n    // ưu tiên v3, fallback v1\n    try {\n      const runs = await fetchJson(API_RUNS_V3);\n      renderRunsTable(runs);\n      return;\n    } catch (e) {\n      console.warn("[VSP] runs_index_v3 error (tab):", e);\n    }\n\n    try {\n      const runs = await fetchJson(API_RUNS_V1);\n      renderRunsTable(runs);\n    } catch (e) {\n      console.warn("[VSP] /api/vsp/runs (v1) error:", e);\n      setNoData(\n        container,\n        "Không load được dữ liệu runs (API /api/vsp/runs_index_v3_v3 và /api/vsp/runs đều chưa sẵn sàng)."\n      );\n    }\n  }\n\n  /* ========== DATA SOURCE TAB ========== */\n\n  async function initDatasourceTab(summary, bySevComputed) {\n    const container = $("vsp-datasource-container");\n    if (!container) return;\n\n    try {\n      const sev =\n        bySevComputed ||\n        summary.by_severity ||\n        summary.severity ||\n        summary.by_severity_buckets ||\n        {};\n\n      let byTool =\n        summary.by_tool ||\n        summary.by_tool_severity ||\n        summary.by_tools ||\n        summary.tools ||\n        {};\n\n      // nếu datasource không có by_tool – thử lấy từ dashboard_v3\n      if (!Object.keys(byTool).length) {\n        try {\n          const dash = await fetchJson(API_DASHBOARD_V3);\n          byTool = dash.by_tool || {};\n        } catch (e) {\n          console.warn("[VSP] dashboard_v3 by_tool fallback error:", e);\n        }\n      }\n\n      const sevRows = SEVERITIES.map((s) => {\n        return (\n          "<tr><td>" +\n          s +\n          "</td><td>" +\n          safeInt(sev[s]) +\n          "</td></tr>"\n        );\n      }).join("");\n\n      const toolKeys = Object.keys(byTool || {});\n      const toolRows = toolKeys\n        .sort()\n        .map((tool) => {\n          const raw = byTool[tool] || {};\n          const d = raw.by_severity || raw.severity || raw;\n          return (\n            "<tr>" +\n            "<td>" + escHtml(tool) + "</td>" +\n            "<td>" + safeInt(d.CRITICAL) + "</td>" +\n            "<td>" + safeInt(d.HIGH) + "</td>" +\n            "<td>" + safeInt(d.MEDIUM) + "</td>" +\n            "<td>" + safeInt(d.LOW) + "</td>" +\n            "</tr>"\n          );\n        })\n        .join("");\n\n      const rightTable =\n        toolKeys.length === 0\n          ? "<p style='font-size:12px;color:#9ca3c7;'>Không có dữ liệu theo tool.</p>"\n          : '<table class="vsp-table">' +\n            "<thead><tr><th>Tool</th><th>CRI</th><th>HIGH</th><th>MED</th><th>LOW</th></tr></thead>" +\n            "<tbody>" + toolRows + "</tbody></table>";\n\n      container.innerHTML =\n        '<div style="display:grid;grid-template-columns:35% 65%;gap:12px;">' +\n        '<div>' +\n        '<h3 style="margin:0 0 6px;font-size:13px;">Tổng quan theo mức độ</h3>' +\n        '<table class="vsp-table">' +\n        "<thead><tr><th>Severity</th><th>Count</th></tr></thead>" +\n        "<tbody>" + sevRows + "</tbody></table>" +\n        "</div>" +\n        '<div>' +\n        '<h3 style="margin:0 0 6px;font-size:13px;">Theo tool</h3>' +\n        rightTable +\n        "</div>" +\n        "</div>";\n    } catch (e) {\n      console.warn("[VSP] initDatasourceTab error:", e);\n      setNoData(\n        container,\n        "Không load được datasource (API /api/vsp/datasource?mode=dashboard chưa sẵn sàng)."\n      );\n    }\n  }\n\n  /* ========== SETTINGS TAB ========== */\n\n  async function initSettingsTab() {\n    const container = $("vsp-settings-container");\n    if (!container) return;\n\n    try {\n      const cfg = await fetchJson(API_SETTINGS);\n      container.innerHTML =\n        "<h3 style='margin:0 0 6px;font-size:13px;'>Cấu hình VSP EXT+ (đọc từ API)</h3>" +\n        "<pre style='font-size:11px;white-space:pre-wrap;border-radius:8px;background:#020617;padding:8px;border:1px solid rgba(148,163,210,0.35);'>" +\n        escHtml(JSON.stringify(cfg, null, 2)) +\n        "</pre>";\n    } catch (e) {\n      console.warn("[VSP] initSettingsTab error:", e);\n      setNoData(\n        container,\n        "Không load được cấu hình (API /api/vsp/settings/get chưa sẵn sàng)."\n      );\n    }\n  }\n\n  /* ========== RULE OVERRIDES TAB ========== */\n\n  async function initOverridesTab() {\n    const container = $("vsp-overrides-container");\n    if (!container) return;\n\n    try {\n      const resp = await fetchJson(API_OVERRIDES);\n      const raw = Array.isArray(resp.items) ? resp.items : resp;\n      let list;\n\n      if (Array.isArray(raw)) {\n        list = raw;\n      } else if (raw && typeof raw === "object") {\n        list = Object.keys(raw).map((k) => raw[k]);\n      } else {\n        throw new Error("invalid overrides format");\n      }\n\n      const rows = list\n        .map((it) => {\n          return (\n            "<tr>" +\n            "<td>" + escHtml(it.id || it.name || "") + "</td>" +\n            "<td>" + escHtml(it.pattern || it.rule || "") + "</td>" +\n            "<td>" + escHtml(it.reason || "") + "</td>" +\n            "</tr>"\n          );\n        })\n        .join("");\n\n      container.innerHTML =\n        "<h3 style='margin:0 0 6px;font-size:13px;'>Rule overrides</h3>" +\n        '<table class="vsp-table">' +\n        "<thead><tr><th>ID</th><th>Pattern / Rule</th><th>Reason</th></tr></thead>" +\n        "<tbody>" + rows + "</tbody></table>";\n    } catch (e) {\n      console.warn("[VSP] initOverridesTab error:", e);\n      setNoData(\n        container,\n        "Không load được danh sách override (API /api/vsp/overrides/list chưa sẵn sàng)."\n      );\n    }\n  }\n\n  /* ========== MAIN LOAD ========== */\n\n  async function loadAll() {\n    try {\n      const resp = await fetchJson(API_SUMMARY);\n      const summary = resp.summary || resp;\n\n      const dash = {\n        run_id: resp.run_id || summary.run_id,\n        ts: resp.ts || summary.ts,\n        total_findings:\n          summary.total_findings ||\n          summary.total ||\n          summary.total_findings_unified,\n      };\n\n      const bySev = await computeSeverityBucketsFromDatasource();\n\n      renderKpisAndDonut(dash, bySev);\n      await initTrend();\n      renderTopCweBar(summary);\n      await initTopFindings();\n\n      await initRunsTab();\n      await initDatasourceTab(summary, bySev);\n      await initSettingsTab();\n      await initOverridesTab();\n    } catch (e) {\n      console.error("[VSP] loadAll error:", e);\n    }\n  }\n\n  window.VSP_DASHBOARD_LIVE_V2_INIT = function () {\n    loadAll().catch((err) => console.error("[VSP] loadAll outer error:", err));\n  };\n})();\n\n\n\n/* ========== TOP CWE FROM INSIGHTS V1 ========== */\n\nfunction renderTopCweBarFromInsights(items) {\n  const canvas = ensureTopCweCanvas();\n  if (!canvas || typeof Chart === "undefined") return;\n\n  const arr = Array.isArray(items) ? items : [];\n  if (!arr.length) {\n    console.debug("[VSP] renderTopCweBarFromInsights: empty items");\n    return;\n  }\n\n  const labels = arr.map((it) => it.cwe || "UNKNOWN");\n  const totals = arr.map((it) => safeInt(it.count || 0));\n\n  if (topCweChart) {\n    try {\n      topCweChart.destroy();\n    } catch (e) {\n      console.warn("[VSP] destroy topCweChart error:", e);\n    }\n  }\n\n  topCweChart = new Chart(canvas, {\n    type: "bar",\n    data: {\n      labels,\n      datasets: [\n        {\n          label: "Findings",\n          data: totals,\n          borderWidth: 1,\n          // Màu để Chart.js tự chọn, UI theme đã lo phần nền\n        }\n      ],\n    },\n    options: {\n      indexAxis: "y",\n      responsive: true,\n      maintainAspectRatio: false,\n      plugins: {\n        legend: { display: false },\n      },\n      scales: {\n        x: {\n          beginAtZero: true,\n          grid: { color: "rgba(148,163,210,0.25)" },\n        },\n        y: {\n          ticks: { autoSkip: false },\n          grid: { display: false },\n        },\n      },\n    },\n  });\n}\n\nasync function initTopCweFromInsights() {\n  if (typeof API_TOP_CWE_V1 === "undefined") {\n    console.warn("[VSP] API_TOP_CWE_V1 not defined – skip Top CWE chart.");\n    return;\n  }\n  try {\n    const data = await fetchJson(API_TOP_CWE_V1 + "?limit=5");\n    const items = data && Array.isArray(data.items) ? data.items : [];\n    if (!items.length) {\n      console.warn("[VSP] top_cwe_v1: no items");\n      return;\n    }\n    renderTopCweBarFromInsights(items);\n  } catch (e) {\n    console.warn("[VSP] top_cwe_v1 error:", e);\n  }\n}\n\n// ======================= TOP_CWE_PATCH_V3 =======================\n// Bind TOP CWE từ /api/vsp/dashboard_v3 (hoặc window.__vspTopCweInit)\n(function () {\n  function bindTopCwe(payload) {\n    try {\n      if (!payload) {\n        console.warn("[VSP][TOP_CWE] Không có payload");\n        return;\n      }\n\n      // Hỗ trợ 2 dạng:\n      // 1) { run_id, top_cwe: [...] }\n      // 2) { ok, payload: { run_id, top_cwe: [...] } }\n      var topList = null;\n\n      if (Array.isArray(payload.top_cwe)) {\n        topList = payload.top_cwe;\n      } else if (payload.payload && Array.isArray(payload.payload.top_cwe)) {\n        topList = payload.payload.top_cwe;\n      }\n\n      if (!topList || !topList.length) {\n        console.warn("[VSP][TOP_CWE] Không có top_cwe trong payload");\n        return;\n      }\n\n      var top = topList[0] || {};\n      var label = top.id || "N/A";\n      var count = (top.count != null) ? top.count : 0;\n\n      var labelNodes = document.querySelectorAll("[data-vsp-topcwe-label]");\n      for (var i = 0; i < labelNodes.length; i++) {\n        labelNodes[i].textContent = label;\n      }\n\n      var countNodes = document.querySelectorAll("[data-vsp-topcwe-count]");\n      for (var j = 0; j < countNodes.length; j++) {\n        countNodes[j].textContent = String(count);\n      }\n\n      console.log("[VSP][TOP_CWE] Bound TOP CWE =", label, "count =", count);\n    } catch (err) {\n      console.error("[VSP][TOP_CWE] bindTopCwe error:", err);\n    }\n  }\n\n  // expose global để chỗ khác gọi được\n  window.__vspBindTopCwe = bindTopCwe;\n\n  function initTopCweFromInsights() {\n    try {\n      if (window.__vspTopCweInit) {\n        console.log("[VSP][TOP_CWE] Dùng window.__vspTopCweInit");\n        bindTopCwe(window.__vspTopCweInit);\n        return;\n      }\n\n      fetch("/api/vsp/dashboard_v3")\n        .then(function (res) {\n          if (!res.ok) {\n            throw new Error("HTTP " + res.status);\n          }\n          return res.json();\n        })\n        .then(function (data) {\n          console.log("[VSP][TOP_CWE] Nhận data từ /api/vsp/dashboard_v3", data);\n          bindTopCwe(data);\n        })\n        .catch(function (err) {\n          console.error("[VSP][TOP_CWE] Fetch /api/vsp/dashboard_v3 lỗi:", err);\n        });\n    } catch (err) {\n      console.error("[VSP][TOP_CWE] initTopCweFromInsights error:", err);\n    }\n  }\n\n  // cũng expose global nếu muốn gọi tay\n  window.initTopCweFromInsights = initTopCweFromInsights;\n\n  document.addEventListener("DOMContentLoaded", function () {\n    try {\n      initTopCweFromInsights();\n    } catch (err) {\n      console.error("[VSP][TOP_CWE] DOMContentLoaded hook error:", err);\n    }\n  });\n})();\n\n// ======================= VSP_ADVANCED_KPI_V1 =======================\n// Bind 4 advanced KPI vào layout CIO-level:\n// - Security Posture Score (0–100)\n// - Top risky tool\n// - Top impacted CWE  (lấy thẳng từ top_cwe[0].id)\n// - Top vulnerable module\n\nfunction vspBindAdvancedKpis(dash) {\n  try {\n    if (!dash) {\n      console.warn("[VSP][ADV_KPI] Không có dashboard data để bind.");\n      return;\n    }\n\n    // 1) Security Posture Score\n    var scoreEl = document.querySelector("[data-vsp-kpi-posture-score]");\n    if (scoreEl) {\n      var score = null;\n      if (typeof dash.security_posture_score === "number") {\n        score = dash.security_posture_score;\n      } else if (dash.security_posture && typeof dash.security_posture.score === "number") {\n        score = dash.security_posture.score;\n      }\n      if (typeof score === "number") {\n        scoreEl.textContent = String(score);\n      } else {\n        scoreEl.textContent = "0";\n      }\n    }\n\n    // 2) Top risky tool\n    var riskyEl = document.querySelector("[data-vsp-kpi-top-risky-tool]");\n    if (riskyEl) {\n      var risky = dash.top_risky_tool\n        || (dash.security_posture && dash.security_posture.top_risky_tool)\n        || null;\n      if (risky && typeof risky.tool === "string") {\n        riskyEl.textContent = risky.tool.toUpperCase();\n      } else if (typeof risky === "string") {\n        riskyEl.textContent = risky.toUpperCase();\n      } else {\n        riskyEl.textContent = "–";\n      }\n    }\n\n    // 3) Top impacted CWE – luôn ưu tiên từ top_cwe[0].id\n    var cweEl = document.querySelector("[data-vsp-kpi-top-cwe]");\n    if (cweEl) {\n      var hiId = null;\n      if (Array.isArray(dash.top_cwe) && dash.top_cwe.length && typeof dash.top_cwe[0].id === "string") {\n        hiId = dash.top_cwe[0].id;\n      } else if (typeof dash.highest_impacted_cwe === "string") {\n        hiId = dash.highest_impacted_cwe;\n      } else if (dash.highest_impacted_cwe && typeof dash.highest_impacted_cwe.id === "string") {\n        hiId = dash.highest_impacted_cwe.id;\n      }\n      cweEl.textContent = hiId || "–";\n    }\n\n    // 4) Top vulnerable module\n    var modEl = document.querySelector("[data-vsp-kpi-top-module]");\n    if (modEl) {\n      var mod = dash.top_vulnerable_module\n        || (dash.security_posture && dash.security_posture.top_vulnerable_module)\n        || null;\n      if (mod && typeof mod.name === "string") {\n        modEl.textContent = mod.name;\n      } else if (typeof mod === "string") {\n        modEl.textContent = mod;\n      } else {\n        modEl.textContent = "–";\n      }\n    }\n\n    console.log("[VSP][ADV_KPI] Bound advanced KPIs (CWE từ top_cwe[0].id).");\n  } catch (err) {\n    console.error("[VSP][ADV_KPI] bind error:", err);\n  }\n}\n\n\n/* ==== END static/js/vsp_dashboard_live_v2.V1_baseline.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_dashboard_live_v2.js ==== */\n\n// === VSP DASHBOARD FIX V3 – CHUẨN 2025 ===\n\n// mapping severity 6 mức chuẩn\nconst VSP_SEVERITY_KEYS = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];\n\n// mapping tool 8 chuẩn\nconst VSP_TOOL_KEYS = [\n  "gitleaks","semgrep","kics","codeql",\n  "bandit","trivy_fs","grype","syft"\n];\n\n// Load KPI vào Dashboard\nfunction vspLoadKPIs(data) {\n  $("#kpi-total").text(data.total_findings);\n\n  // by severity\n  VSP_SEVERITY_KEYS.forEach(sev => {\n    const el = $("#kpi-" + sev.toLowerCase());\n    el.text(data.by_severity[sev] || 0);\n    el.addClass("sev-" + sev.toLowerCase());\n  });\n\n  // by tool\n  VSP_TOOL_KEYS.forEach(tool => {\n    $("#kpi-tool-" + tool).text(data.by_tool[tool] || 0);\n  });\n\n  $("#kpi-top-cwe").text(data.top_cwe || "N/A");\n  $("#kpi-top-module").text(data.top_module || "N/A");\n  $("#kpi-top-risky-tool").text(data.top_risky_tool || "N/A");\n}\n\n// MAIN fetch\nfunction loadDashboard() {\n  fetch("/api/vsp/dashboard_v3")\n    .then(r => r.json())\n    .then(json => {\n      if (!json.ok) return console.error("[DASHBOARD] JSON not ok");\n      vspLoadKPIs(json);\n      drawCharts(json); // gọi chart\n    })\n    .catch(err => console.error("[DASHBOARD] Error", err));\n}\n\ndocument.addEventListener("DOMContentLoaded", loadDashboard);\n\n\n/* ======================= VSP_DASHBOARD_KPI_V2 – BEGIN ======================= */\n\nwindow.vspDashboardApplyExtrasV1 = function(extras) {\n  try {\n    if (!extras) return;\n    window.vspApplyKpiDiffFromExtras(extras);\n    window.vspRenderTopRiskFromExtras(extras);\n  } catch (e) {\n    console && console.warn && console.warn("[VSP][KPI_V2] Error apply extras:", e);\n  }\n};\n\nwindow.vspApplyKpiDiffFromExtras = function(extras) {\n  try {\n    if (!extras || !extras.kpi_diff_v1) return;\n    var diff  = extras.kpi_diff_v1;\n    var cur   = diff.current || {};\n    var prev  = diff.prev   || {};\n    var delta = diff.delta  || {};\n\n    // Last run label: PREV → CURRENT\n    var prevId = prev.run_id || "N/A";\n    var curId  = cur.run_id  || "N/A";\n    var lastRunLabel = prevId + " \u2192 " + curId; // arrow\n\n    // Delta total + chi tiết từng severity\n    var dTotal = delta.total_findings || 0;\n    var signTotal = dTotal > 0 ? "+" : "";\n    var baseText = signTotal + dTotal + " findings vs prev";\n\n    var sevOrder = ["CRITICAL", "HIGH", "MEDIUM", "LOW"];\n    var sevParts = [];\n    if (delta.by_severity) {\n      sevOrder.forEach(function(s) {\n        var v = delta.by_severity.hasOwnProperty(s)\n          ? delta.by_severity[s]\n          : 0;\n        if (!v) return;\n        var sign = v > 0 ? "+" : "";\n        sevParts.push(sign + v + " " + s);\n      });\n    }\n    var details = sevParts.length ? " (" + sevParts.join(", ") + ")" : "";\n    var deltaText = baseText + details;\n\n    var elLast = document.getElementById("kpi-last-run-label");\n    if (!elLast) {\n      elLast = document.querySelector("[data-kpi-last-run]");\n    }\n    if (elLast) {\n      elLast.textContent = lastRunLabel;\n    }\n\n    var elDelta = document.getElementById("kpi-delta-label");\n    if (!elDelta) {\n      elDelta = document.querySelector("[data-kpi-delta]");\n    }\n    if (elDelta) {\n      elDelta.textContent = deltaText;\n    }\n\n    if (window.console && console.log) {\n      console.log("[VSP][KPI_V2] Applied KPI diff extras.");\n    }\n  } catch (e) {\n    console && console.warn && console.warn("[VSP][KPI_V2] Error in vspApplyKpiDiffFromExtras:", e);\n  }\n};\n\nwindow.vspRenderTopRiskFromExtras = function(extras) {\n  try {\n    if (!extras || !extras.top_risk_findings) return;\n    var items = extras.top_risk_findings;\n    if (!Array.isArray(items) || items.length === 0) return;\n\n    var tbody = document.getElementById("vsp-top-risk-tbody");\n    if (!tbody) {\n      tbody = document.querySelector("tbody[data-top-risk-body]");\n    }\n    if (!tbody) {\n      return;\n    }\n\n    while (tbody.firstChild) {\n      tbody.removeChild(tbody.firstChild);\n    }\n\n    items.forEach(function(it, idx) {\n      var tr = document.createElement("tr");\n\n      var tdIdx  = document.createElement("td");\n      var tdSev  = document.createElement("td");\n      var tdTool = document.createElement("td");\n      var tdFile = document.createElement("td");\n      var tdRule = document.createElement("td");\n\n      tdIdx.textContent  = String(idx + 1);\n\n      // Severity badge + palette\n      var sev = (it.severity || "").toUpperCase();\n      tdSev.textContent = sev;\n      var cls = "sev-" + sev.toLowerCase();\n      tdSev.classList.add("sev-pill");\n      tdSev.classList.add(cls);\n\n      tdTool.textContent = it.tool || "";\n\n      var fileLabel = it.file || "";\n      if (it.line) {\n        fileLabel += ":" + it.line;\n      }\n      tdFile.textContent = fileLabel;\n\n      // Rule / CWE gọn đẹp\n      var rule = it.rule_id || "";\n      var cwe  = it.cwe || "";\n      var label = "";\n      if (rule && cwe) {\n        label = rule + " \u2022 " + cwe; // bullet giữa\n      } else if (rule) {\n        label = rule;\n      } else if (cwe) {\n        label = cwe;\n      }\n      // Cắt ngắn nếu quá dài\n      var maxLen = 60;\n      if (label.length > maxLen) {\n        label = label.slice(0, maxLen - 1) + "\u2026";\n      }\n      tdRule.textContent = label;\n\n      tr.appendChild(tdIdx);\n      tr.appendChild(tdSev);\n      tr.appendChild(tdTool);\n      tr.appendChild(tdFile);\n      tr.appendChild(tdRule);\n\n      tbody.appendChild(tr);\n    });\n\n    if (window.console && console.log) {\n      console.log("[VSP][KPI_V2] Rendered top_risk_findings:", items.length);\n    }\n  } catch (e) {\n    console && console.warn && console.warn("[VSP][KPI_V2] Error in vspRenderTopRiskFromExtras:", e);\n  }\n};\n\n/* ======================= VSP_DASHBOARD_KPI_V2 – END ========================= */\n\n\n/* ======================= VSP_DASHBOARD_KPI_V3 – BEGIN ======================= */\n\nwindow.vspDashboardApplyExtrasV1 = function(extras) {\n  try {\n    if (!extras) return;\n    window.vspApplyKpiDiffFromExtras(extras);\n    window.vspRenderTopRiskFromExtras(extras);\n  } catch (e) {\n    console && console.warn && console.warn("[VSP][KPI_V3] Error apply extras:", e);\n  }\n};\n\nwindow.vspApplyKpiDiffFromExtras = function(extras) {\n  try {\n    if (!extras || !extras.kpi_diff_v1) return;\n    var diff  = extras.kpi_diff_v1;\n    var cur   = diff.current || {};\n    var prev  = diff.prev   || {};\n    var delta = diff.delta  || {};\n\n    // Last run label: PREV → CURRENT\n    var prevId = prev.run_id || "N/A";\n    var curId  = cur.run_id  || "N/A";\n    var lastRunLabel = prevId + " \u2192 " + curId; // arrow\n\n    // Delta total\n    var dTotal = delta.total_findings || 0;\n    var signTotal = dTotal > 0 ? "+" : (dTotal < 0 ? "" : ""); // âm tự có dấu '-'\n    var baseText = signTotal + dTotal + " findings vs prev";\n\n    // Delta chi tiết 6 severity\n    var sevOrder = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "TRACE"];\n    var sevParts = [];\n    if (delta.by_severity) {\n      sevOrder.forEach(function(s) {\n        var raw = delta.by_severity.hasOwnProperty(s)\n          ? delta.by_severity[s]\n          : 0;\n        var v = raw || 0;\n        if (!v) return; // bỏ những cái = 0 cho gọn\n        var sign = v > 0 ? "+" : ""; // âm tự có '-'\n        sevParts.push(sign + v + " " + s);\n      });\n    }\n    var details = sevParts.length ? " (" + sevParts.join(", ") + ")" : "";\n    var deltaText = baseText + details;\n\n    // Update DOM\n    var elLast = document.getElementById("kpi-last-run-label");\n    if (!elLast) {\n      elLast = document.querySelector("[data-kpi-last-run]");\n    }\n    if (elLast) {\n      elLast.textContent = lastRunLabel;\n    }\n\n    var elDelta = document.getElementById("kpi-delta-label");\n    if (!elDelta) {\n      elDelta = document.querySelector("[data-kpi-delta]");\n    }\n    if (elDelta) {\n      // reset class cũ\n      elDelta.classList.remove("kpi-delta-bad", "kpi-delta-good", "kpi-delta-neutral");\n      elDelta.textContent = deltaText;\n      if (dTotal > 0) {\n        elDelta.classList.add("kpi-delta-bad");\n      } else if (dTotal < 0) {\n        elDelta.classList.add("kpi-delta-good");\n      } else {\n        elDelta.classList.add("kpi-delta-neutral");\n      }\n    }\n\n    if (window.console && console.log) {\n      console.log("[VSP][KPI_V3] Applied KPI diff extras.");\n    }\n  } catch (e) {\n    console && console.warn && console.warn("[VSP][KPI_V3] Error in vspApplyKpiDiffFromExtras:", e);\n  }\n};\n\nwindow.vspRenderTopRiskFromExtras = function(extras) {\n  try {\n    if (!extras || !extras.top_risk_findings) return;\n    var items = extras.top_risk_findings;\n    if (!Array.isArray(items) || items.length === 0) return;\n\n    var tbody = document.getElementById("vsp-top-risk-tbody");\n    if (!tbody) {\n      tbody = document.querySelector("tbody[data-top-risk-body]");\n    }\n    if (!tbody) {\n      return;\n    }\n\n    while (tbody.firstChild) {\n      tbody.removeChild(tbody.firstChild);\n    }\n\n    items.forEach(function(it, idx) {\n      var tr = document.createElement("tr");\n\n      var tdIdx  = document.createElement("td");\n      var tdSev  = document.createElement("td");\n      var tdTool = document.createElement("td");\n      var tdFile = document.createElement("td");\n      var tdRule = document.createElement("td");\n\n      tdIdx.textContent  = String(idx + 1);\n\n      // Severity badge + palette\n      var sev = (it.severity || "").toUpperCase();\n      tdSev.textContent = sev;\n      var sevCls = "sev-" + sev.toLowerCase(); // sev-critical, sev-high, ...\n      tdSev.classList.add("sev-pill");\n      tdSev.classList.add(sevCls);\n\n      tdTool.textContent = it.tool || "";\n\n      var fileLabel = it.file || "";\n      if (it.line) {\n        fileLabel += ":" + it.line;\n      }\n      tdFile.textContent = fileLabel;\n\n      // Rule / CWE gọn đẹp\n      var rule = it.rule_id || "";\n      var cwe  = it.cwe || "";\n      var label = "";\n      if (rule && cwe) {\n        label = rule + " \u2022 " + cwe; // bullet giữa\n      } else if (rule) {\n        label = rule;\n      } else if (cwe) {\n        label = cwe;\n      }\n      var maxLen = 60;\n      if (label.length > maxLen) {\n        label = label.slice(0, maxLen - 1) + "\u2026";\n      }\n      tdRule.textContent = label;\n\n      tr.appendChild(tdIdx);\n      tr.appendChild(tdSev);\n      tr.appendChild(tdTool);\n      tr.appendChild(tdFile);\n      tr.appendChild(tdRule);\n\n      tbody.appendChild(tr);\n    });\n\n    if (window.console && console.log) {\n      console.log("[VSP][KPI_V3] Rendered top_risk_findings:", items.length);\n    }\n  } catch (e) {\n    console && console.warn && console.warn("[VSP][KPI_V3] Error in vspRenderTopRiskFromExtras:", e);\n  }\n};\n\n/* ======================= VSP_DASHBOARD_KPI_V3 – END ========================= */\n// ===================== VSP RUNS TABLE META V1 =====================\n\nfunction vspRenderRunsTable(runs) {\n  const tbody = document.getElementById("vsp-runs-tbody");\n  if (!tbody) return;\n\n  tbody.innerHTML = "";\n\n  runs.forEach(run => {\n    const row = document.createElement("tr");\n    const sev = run.by_severity || {};\n    const tools = run.by_tool ? Object.keys(run.by_tool).length : 0;\n\n    const ts = run.timestamp || "";\n    const profile = run.profile || "";\n    const src = run.src_path || "";\n    const url = run.entry_url || "";\n\n    const urlShort = url\n      ? (url.length > 40 ? url.slice(0, 37) + "..." : url)\n      : "";\n\n    row.innerHTML = `\n      <td class="vsp-cell-runid">\${run.run_id || ""}</td>\n      <td>\${ts}</td>\n      <td>\${profile}</td>\n      <td>\${src}</td>\n      <td>${url ? `<a href="${url}" target="_blank" rel="noopener noreferrer">\${urlShort}</a>` : ""}</td>\n      <td>\${run.total_findings || 0}</td>\n      <td>\${sev.CRITICAL || 0}</td>\n      <td>\${sev.HIGH || 0}</td>\n      <td>\${sev.MEDIUM || 0}</td>\n      <td>\${sev.LOW || 0}</td>\n      <td>\${sev.INFO || 0}</td>\n      <td>\${sev.TRACE || 0}</td>\n      <td>\${tools}</td>\n      <td><span class="vsp-tag vsp-tag-muted">N/A</span></td>\n    `;\n    tbody.appendChild(row);\n  });\n}\n\nasync function vspLoadRunsIndexV3() {\n  try {\n    const res = await fetch("/api/vsp/runs_index_v3");\n    if (!res.ok) {\n      console.error("[RUNS] HTTP error", res.status);\n      return;\n    }\n    const runs = await res.json();\n    if (!Array.isArray(runs)) {\n      console.error("[RUNS] Unexpected payload", runs);\n      return;\n    }\n    vspRenderRunsTable(runs);\n  } catch (err) {\n    console.error("[RUNS] Failed to load runs_index_v3:", err);\n  }\n}\n// =================== END VSP RUNS TABLE META V1 ====================\n\n// ================= VSP_SETTINGS_PROFILE_RULES_V1 =================\n\n// Load settings JSON, có fallback demo\nasync function vspLoadSettingsProfileV1() {\n  try {\n    const res = await fetch("/static/data/vsp_settings_profile_v1.json?_=" + Date.now());\n    if (!res.ok) throw new Error("HTTP " + res.status);\n    const js = await res.json();\n    return js;\n  } catch (e) {\n    console.warn("[VSP_SETTINGS] Không load được settings_profile_v1, dùng demo. Lý do:", e);\n    return {\n      profile_name: "VSP_FULL_EXT_2025",\n      env: "STAGING / DEMO",\n      run_id_latest: "RUN_VSP_FULL_EXT_DEMO",\n      security_score: 0,\n      tools: [\n        { id: "bandit", name: "bandit", type: "SAST", mode: "EXT", enabled: true, findings: 0, severity_min: "LOW" },\n        { id: "gitleaks", name: "gitleaks", type: "Secrets", mode: "EXT", enabled: true, findings: 0, severity_min: "HIGH" },\n        { id: "kics", name: "kics", type: "IaC", mode: "EXT", enabled: true, findings: 0, severity_min: "MEDIUM" },\n      ],\n      profiles: [\n        { id: "FULL_EXT", label: "Full EXT (all tools)", tools: ["bandit","gitleaks","kics"], description: "Full extended profile – all tools enabled." }\n      ]\n    };\n  }\n}\n\n// Render Tab 4 – Settings / Profile / Tools\nasync function vspInitSettingsTabV1() {\n  const panel = document.querySelector('.vsp-tab-panel[data-tab="4"]');\n  if (!panel) {\n    console.warn("[VSP_SETTINGS] Không thấy panel Tab 4.");\n    return;\n  }\n\n  const cfg = await vspLoadSettingsProfileV1();\n  const tools = Array.isArray(cfg.tools) ? cfg.tools : [];\n  const profiles = Array.isArray(cfg.profiles) ? cfg.profiles : [];\n\n  let toolsRows = "";\n  tools.forEach((t, idx) => {\n    const badge = t.enabled ? "Enabled" : "Disabled";\n    const badgeClass = t.enabled ? "status-badge status-ok" : "status-badge status-off";\n    toolsRows += `\n      <tr>\n        <td>${idx + 1}</td>\n        <td>${t.id}</td>\n        <td>${t.type || "-"}</td>\n        <td>${t.mode || "-"}</td>\n        <td>${t.severity_min || "-"}</td>\n        <td>${t.findings != null ? t.findings : "-"}</td>\n        <td><span class="${badgeClass}">${badge}</span></td>\n      </tr>\n    `;\n  });\n\n  let profilesRows = "";\n  profiles.forEach((p, idx) => {\n    profilesRows += `\n      <tr>\n        <td>${idx + 1}</td>\n        <td>${p.id}</td>\n        <td>${p.label || "-"}</td>\n        <td>${(p.tools || []).join(", ")}</td>\n        <td>${p.description || "-"}</td>\n      </tr>\n    `;\n  });\n\n  panel.innerHTML = `\n    <div class="vsp-section-header">\n      <div class="vsp-section-title">Tab 4 – Settings / Profile / Tools</div>\n      <div class="vsp-section-subtitle">Scan profile &amp; tool configuration (read-only)</div>\n    </div>\n\n    <div class="vsp-grid vsp-grid-2">\n      <div class="vsp-card">\n        <div class="vsp-card-title">Profile overview</div>\n        <div class="vsp-card-body">\n          <div class="vsp-metric-line"><span>Active profile:</span><span>${cfg.profile_name || "-"}</span></div>\n          <div class="vsp-metric-line"><span>Environment:</span><span>${cfg.env || "-"}</span></div>\n          <div class="vsp-metric-line"><span>Latest run:</span><span>${cfg.run_id_latest || "-"}</span></div>\n          <div class="vsp-metric-line"><span>Security posture score:</span><span>${cfg.security_score || 0} / 100</span></div>\n          <div class="vsp-metric-line"><span>Tools enabled:</span><span>${tools.length}</span></div>\n        </div>\n      </div>\n\n      <div class="vsp-card">\n        <div class="vsp-card-title">Profiles</div>\n        <div class="vsp-card-body">\n          <div class="vsp-table-wrapper">\n            <table class="vsp-table compact">\n              <thead>\n                <tr>\n                  <th>#</th>\n                  <th>ID</th>\n                  <th>Label</th>\n                  <th>Tools</th>\n                  <th>Description</th>\n                </tr>\n              </thead>\n              <tbody>\n                ${profilesRows || `<tr><td colspan="5" style="text-align:center;opacity:.6;">No profiles defined.</td></tr>`}\n              </tbody>\n            </table>\n          </div>\n        </div>\n      </div>\n    </div>\n\n    <div class="vsp-card vsp-card-fullwidth">\n      <div class="vsp-card-title">Tools configuration</div>\n      <div class="vsp-card-body">\n        <div class="vsp-table-wrapper">\n          <table class="vsp-table compact">\n            <thead>\n              <tr>\n                <th>#</th>\n                <th>Tool</th>\n                <th>Type</th>\n                <th>Mode</th>\n                <th>Severity min</th>\n                <th>Findings (latest run)</th>\n                <th>Status</th>\n              </tr>\n            </thead>\n            <tbody>\n              ${toolsRows || `<tr><td colspan="7" style="text-align:center;opacity:.6;">No tools found.</td></tr>`}\n            </tbody>\n          </table>\n        </div>\n      </div>\n    </div>\n  `;\n}\n\n// Render Tab 5 – Rule Overrides (read-only)\nasync function vspInitRuleOverridesTabV1() {\n  const panel = document.querySelector('.vsp-tab-panel[data-tab="5"]');\n  if (!panel) {\n    console.warn("[VSP_RULES] Không thấy panel Tab 5.");\n    return;\n  }\n\n  // Thử load file overrides nếu sau này bạn có, còn hiện tại coi như chưa cấu hình\n  let overrides = [];\n  try {\n    const res = await fetch("/static/data/vsp_rule_overrides_v1.json?_=" + Date.now());\n    if (res.ok) {\n      const js = await res.json();\n      if (Array.isArray(js)) overrides = js;\n      else if (Array.isArray(js.items)) overrides = js.items;\n    }\n  } catch (e) {\n    console.warn("[VSP_RULES] Không load được vsp_rule_overrides_v1.json:", e);\n  }\n\n  let rows = "";\n  overrides.forEach((ov, idx) => {\n    rows += `\n      <tr>\n        <td>${idx + 1}</td>\n        <td>${ov.tool || "-"}</td>\n        <td>${ov.rule_id || "-"}</td>\n        <td>${ov.rule_name || "-"}</td>\n        <td>${ov.severity_raw || "-"}</td>\n        <td>${ov.severity_effective || "-"}</td>\n        <td>${ov.reason || "-"}</td>\n      </tr>\n    `;\n  });\n\n  panel.innerHTML = `\n    <div class="vsp-section-header">\n      <div class="vsp-section-title">Tab 5 – Rule overrides</div>\n      <div class="vsp-section-subtitle">View / audit severity overrides &amp; rule tuning (read-only)</div>\n    </div>\n\n    <div class="vsp-card vsp-card-fullwidth">\n      <div class="vsp-card-title">Overrides registry</div>\n      <div class="vsp-card-body">\n        <div class="vsp-table-wrapper">\n          <table class="vsp-table compact">\n            <thead>\n              <tr>\n                <th>#</th>\n                <th>Tool</th>\n                <th>Rule ID</th>\n                <th>Rule name</th>\n                <th>Severity raw</th>\n                <th>Severity effective</th>\n                <th>Reason</th>\n              </tr>\n            </thead>\n            <tbody>\n              ${rows || `<tr><td colspan="7" style="text-align:center;opacity:.6;">No rule overrides configured.</td></tr>`}\n            </tbody>\n          </table>\n        </div>\n        <div style="margin-top:12px;opacity:.7;font-size:12px;">\n          This view is read-only in demo. Production edition can load overrides from central config\n          (YAML/JSON) and allow export for ISO 27001 / DevSecOps audits.\n        </div>\n      </div>\n    </div>\n  `;\n}\n\n// Gắn init vào DOMContentLoaded của Dashboard\ndocument.addEventListener("DOMContentLoaded", function () {\n  vspInitSettingsTabV1();\n  vspInitRuleOverridesTabV1();\n});\n\n// ================= END VSP_SETTINGS_PROFILE_RULES_V1 =================\n\n\n\n/* ==== END static/js/vsp_dashboard_live_v2.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_dashboard_tables_live_v1.js ==== */\n\n(function () {\n  'use strict';\n\n  const API_TABLES       = '/api/vsp/dashboard_v3_tables';\n  const API_TOP_FINDINGS = '/api/vsp/datasource?severity=HIGH&limit=10';\n\n  function findTbodyByTitle(titleText) {\n    var all = document.querySelectorAll('*');\n    var titleEl = null;\n\n    for (var i = 0; i < all.length; i++) {\n      var txt = (all[i].textContent || '').trim();\n      if (txt === titleText) {\n        titleEl = all[i];\n        break;\n      }\n    }\n    if (!titleEl) return null;\n\n    var card = titleEl;\n    for (var depth = 0; depth < 6 && card; depth++) {\n      var tbody = card.querySelector('tbody');\n      if (tbody) return tbody;\n      card = card.parentElement;\n    }\n    return null;\n  }\n\n  // -------- Top Findings (chi tiết từ datasource HIGH) ----------\n  function renderTopFindings(items) {\n    var tbody = findTbodyByTitle('Top Findings');\n    if (!tbody) return;\n\n    tbody.innerHTML = '';\n\n    if (!Array.isArray(items) || items.length === 0) {\n      var tr = document.createElement('tr');\n      var td = document.createElement('td');\n      td.colSpan = 5;\n      td.textContent = 'No data from latest FULL EXT run.';\n      tr.appendChild(td);\n      tbody.appendChild(tr);\n      return;\n    }\n\n    items.forEach(function (f) {\n      var tr = document.createElement('tr');\n\n      var sev  = (f.severity || f.sev || '').toString().toUpperCase();\n      var tool = f.tool || f.source || '';\n      var rule = f.rule_id || f.rule || f.check_id || '';\n      var file = f.file || f.path || f.relpath || '';\n      var msg  = f.message || f.detail || f.title || '';\n\n      function cell(text) {\n        var td = document.createElement('td');\n        td.textContent = text;\n        tr.appendChild(td);\n      }\n\n      cell(sev);\n      cell(tool);\n      cell(rule);\n      cell(file);\n      cell(msg);\n\n      tbody.appendChild(tr);\n    });\n  }\n\n  function loadTopFindings() {\n    fetch(API_TOP_FINDINGS)\n      .then(function (r) { return r.json(); })\n      .then(function (data) {\n        if (!data || data.ok === false) {\n          console.warn('[VSP][TABLE] datasource HIGH not ok:', data);\n          return;\n        }\n        renderTopFindings(data.items || []);\n      })\n      .catch(function (err) {\n        console.error('[VSP][TABLE] fetch Top Findings error:', err);\n      });\n  }\n\n  // -------- Top CVE / CWE ----------\n  function renderTopCve(list) {\n    var tbody = findTbodyByTitle('Top CVE');\n    if (!tbody) return;\n\n    tbody.innerHTML = '';\n\n    if (!Array.isArray(list) || list.length === 0) {\n      var tr = document.createElement('tr');\n      var td = document.createElement('td');\n      td.colSpan = 2;\n      td.textContent = 'No data from latest FULL EXT run.';\n      tr.appendChild(td);\n      tbody.appendChild(tr);\n      return;\n    }\n\n    list.forEach(function (row) {\n      var tr = document.createElement('tr');\n\n      var id = row.cve || row.cwe || row.id || '-';\n      var count = row.count || 0;\n\n      var td1 = document.createElement('td');\n      td1.textContent = id;\n      tr.appendChild(td1);\n\n      var td2 = document.createElement('td');\n      td2.textContent = String(count);\n      tr.appendChild(td2);\n\n      tbody.appendChild(tr);\n    });\n  }\n\n  // -------- Top Modules ----------\n  function renderTopModules(list, topDirs) {\n    var tbody = findTbodyByTitle('Top Modules');\n    if (!tbody) return;\n\n    tbody.innerHTML = '';\n\n    // Nếu BE chưa có summary.top_modules → tự build từ top_dirs\n    if (!Array.isArray(list) || list.length === 0) {\n      list = [];\n      if (Array.isArray(topDirs)) {\n        topDirs.forEach(function (d) {\n          list.push({\n            name: d.path || '',\n            total: d.total || 0,\n            crit_high: (d.CRIT || 0) + (d.HIGH || 0)\n          });\n        });\n      }\n    }\n\n    if (!Array.isArray(list) || list.length === 0) {\n      var tr = document.createElement('tr');\n      var td = document.createElement('td');\n      td.colSpan = 3;\n      td.textContent = 'No data from latest FULL EXT run.';\n      tr.appendChild(td);\n      tbody.appendChild(tr);\n      return;\n    }\n\n    list.forEach(function (row) {\n      var tr = document.createElement('tr');\n\n      var name = row.name || row.module || row.package || '-';\n      var total = row.total || 0;\n      var ch = row.crit_high || row.CRIT_HIGH || 0;\n\n      function cell(text) {\n        var td = document.createElement('td');\n        td.textContent = String(text);\n        tr.appendChild(td);\n      }\n\n      cell(name);\n      cell(total);\n      cell(ch);\n\n      tbody.appendChild(tr);\n    });\n  }\n\n  function loadTables() {\n    fetch(API_TABLES)\n      .then(function (r) { return r.json(); })\n      .then(function (data) {\n        if (!data || data.ok === false) {\n          console.warn('[VSP][TABLE] /api/vsp/dashboard_v3_tables not ok:', data);\n          return;\n        }\n        var topCweList = data.top_cve_list || data.top_cwe_list || [];\n        var topModules = data.top_modules || [];\n        var topDirs    = data.top_dirs || [];\n\n        renderTopCve(topCweList);\n        renderTopModules(topModules, topDirs);\n      })\n      .catch(function (err) {\n        console.error('[VSP][TABLE] fetch dashboard_tables error:', err);\n      });\n  }\n\n  document.addEventListener('DOMContentLoaded', function () {\n    loadTopFindings();\n    loadTables();\n  });\n})();\n\n\n/* ==== END static/js/vsp_dashboard_tables_live_v1.js ==== */\n;\n;\n/* ==== BEGIN static/js/vsp_dashboard_top_module_dom_v1.js ==== */\n\n(function () {\n  const LOG_PREFIX = "[VSP_TOP_MODULE_DOM]";\n\n  function cleanupOnce() {\n    try {\n      const root = document.querySelector("#vsp-root") || document;\n      if (!root) return;\n\n      // Tìm phần tử có text "Top vulnerable module"\n      const all = Array.from(root.querySelectorAll("*"));\n      const labelEls = all.filter((el) => {\n        if (!el || !el.textContent) return false;\n        return el.textContent.trim() === "Top vulnerable module";\n      });\n\n      if (!labelEls.length) return;\n\n      labelEls.forEach((labelEl) => {\n        let valueEl = labelEl.nextElementSibling;\n        if (!valueEl) {\n          // thử tìm trong cùng block\n          const parent = labelEl.parentElement;\n          if (!parent) return;\n          const candidates = Array.from(parent.children).filter((c) => c !== labelEl);\n          valueEl = candidates[0] || null;\n        }\n        if (!valueEl) return;\n\n        const raw = (valueEl.textContent || "").trim();\n        if (!raw) return;\n\n        let textOut = raw;\n\n        // Nếu là JSON thì parse -> label/path/id\n        try {\n          const parsed = JSON.parse(raw);\n          if (parsed && typeof parsed === "object") {\n            textOut =\n              parsed.label ||\n              parsed.path ||\n              parsed.id ||\n              raw;\n          }\n        } catch (e) {\n          // không phải JSON thì giữ nguyên\n        }\n\n        if (textOut && textOut.length > 80) {\n          textOut = textOut.slice(0, 77) + "...";\n        }\n\n        if (textOut && textOut !== raw) {\n          console.log(LOG_PREFIX, "Normalize top module:", raw, "=>", textOut);\n          valueEl.textContent = textOut;\n        }\n      });\n    } catch (err) {\n      console.error(LOG_PREFIX, "cleanup error:", err);\n    }\n  }\n\n  function startWatcher() {\n    let tries = 0;\n    const maxTries = 30; // ~15s nếu 500ms/lần\n\n    const timer = setInterval(() => {\n      tries += 1;\n      cleanupOnce();\n      if (tries >= maxTries) {\n        clearInterval(timer);\n      }\n    }, 500);\n  }\n\n  // Chạy khi load xong\n  if (document.readyState === "complete" || document.readyState === "interactive") {\n    startWatcher();\n  } else {\n    window.addEventListener("DOMContentLoaded", startWatcher);\n  }\n\n  // Nếu dashboard có trigger event custom thì cũng bắt thêm\n  window.addEventListener("vspDashboardV3Rendered", function () {\n    console.log(LOG_PREFIX, "Received vspDashboardV3Rendered event");\n    cleanupOnce();\n  });\n})();\n\n\n/* ==== END static/js/vsp_dashboard_top_module_dom_v1.js ==== */\n;\n\n/* VSP_DRILLDOWN_HARDLOCK_FOOTER_P0_V1 */\n(function(){\n  'use strict';\n  function _dd(intent){\n    try{\n      if (typeof window.VSP_DRILLDOWN_IMPL === 'function') return window.VSP_DRILLDOWN_IMPL(intent);\n      if (typeof window.VSP_DRILLDOWN === 'function') return window.VSP_DRILLDOWN(intent);\n      return null;\n    }catch(e){ return null; }\n  }\n  function hard(name){\n    try{\n      var f = function(intent){ return _dd(intent); };\n      // lock symbol to function to prevent overwrite by legacy modules\n      try{\n        Object.defineProperty(window, name, {value:f, writable:false, configurable:false});\n      }catch(_){\n        window[name] = f;\n      }\n      // also keep legacy namespace compat\n      try{ window.P1_V2 = window.P1_V2 || {}; window.P1_V2.drilldown = f; }catch(__){}\n    }catch(_e){}\n  }\n  hard("VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2");\n  hard("VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V1");\n  hard("VSP_DASH_DRILLDOWN_ARTIFACTS");\n})();\n\n