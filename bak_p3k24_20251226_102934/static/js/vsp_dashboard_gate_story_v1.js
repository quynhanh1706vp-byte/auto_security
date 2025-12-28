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
