
/* === VSP_P3K24_MIN_COMMERCIAL_SAFE_V1 ===
   Rules:
   - If URL has ?rid= => do NOT call /api/vsp/rid_latest* (return url rid immediately)
   - Swallow Firefox noise: timeout / NetworkError / AbortError / NS_BINDING_ABORTED
   - Never throw "timeout" to console as unhandled rejection
*/
(function(){
  try{
    if (window.__VSP_P3K24_SAFE__) return;
    window.__VSP_P3K24_SAFE__ = true;

    function _urlRid(){
      try{
        const sp = new URLSearchParams(location.search || "");
        return (sp.get("rid") || "").trim();
      }catch(e){ return ""; }
    }

    const RID_URL = _urlRid();
    if (RID_URL) {
      window.__VSP_RID_URL__ = RID_URL;
      window.__VSP_AUTORID_DISABLED__ = true;
    }

    function _msg(x){
      try{
        if (typeof x === "string") return x;
        if (!x) return "";
        return (x.message || x.toString || "").toString();
      }catch(e){ return ""; }
    }

    function _isNoise(reason){
      const m = _msg(reason);
      return /timeout|networkerror|aborterror|ns_binding_aborted/i.test(m);
    }

    // 1) Stop "Uncaught (in promise) timeout" from poisoning console
    window.addEventListener("unhandledrejection", function(ev){
      try{
        if (ev && _isNoise(ev.reason)) {
          ev.preventDefault && ev.preventDefault();
        }
      }catch(e){}
    }, true);

    // 2) If rid is in URL, short-circuit fetch() calls to rid_latest endpoints
    if (RID_URL && typeof window.fetch === "function") {
      const _fetch = window.fetch.bind(window);
      window.fetch = function(input, init){
        try{
          const url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
          if (/\/api\/vsp\/rid_latest(_v3|_gate_root)?(\?|$)/.test(String(url))) {
            const body = JSON.stringify({ok:true, rid: RID_URL, mode:"url"});
            return Promise.resolve(new Response(body, {status:200, headers: {"Content-Type":"application/json; charset=utf-8","Cache-Control":"no-store"}}));
          }
        }catch(e){}
        return _fetch(input, init);
      };
    }

    // 3) Utility for other scripts
    window.__VSP_SAFE_WRAP_PROMISE__ = function(p){
      try{
        return Promise.resolve(p).catch(function(e){
          if (_isNoise(e)) return null;
          throw e;
        });
      }catch(e){ return Promise.resolve(null); }
    };

  }catch(e){}
})();

/* === VSP_P3K19_EARLY_GUARD_SWALLOW_TIMEOUT_V1 ===
   Run EARLY (before tabs5) to suppress "Uncaught (in promise) timeout" in Firefox.
=== */
(function(){
  function _isTimeoutMsg(m){
    try {
      m = (m && (m.message || (''+m))) || '';
      return (m === 'timeout') || (/\btimeout\b/i.test(m));
    } catch(_){ return false; }
  }
  try {
    if (!window.__VSP_TIMEOUT_GUARD__) {
      window.__VSP_TIMEOUT_GUARD__ = true;
      window.addEventListener('unhandledrejection', function(e){
        try { if (_isTimeoutMsg(e && e.reason)) e.preventDefault(); } catch(_){}
      });
      window.addEventListener('error', function(e){
        try {
          var msg = (e && (e.message || (''+e.error))) || '';
          if (_isTimeoutMsg(msg)) e.preventDefault();
        } catch(_){}
      }, true);
    }
  } catch(_){}
})();

/* VSP_FALLBACK_GATE_STORY_V1 (no-op, prevents crash) */
(function(){
  try{
    window.VSP_GATE_STORY = window.VSP_GATE_STORY || {};
    window.VSP_GATE_STORY.init = window.VSP_GATE_STORY.init || function(){ console.log("[VSP][FALLBACK] gate_story init"); };
    console.log("[VSP][FALLBACK] vsp_dashboard_gate_story_v1.js loaded (fallback)");
  }catch(e){}
})();
