/* === VSP_P3K22_EARLY_SAFE_SHIM_V1 ===
   Run BEFORE other scripts (autorid/tabs5) to avoid Firefox abort/noise.
   - If ?rid= exists: short-circuit /api/vsp/rid_latest* to return URL rid immediately.
   - Rewrite XHR rid_latest -> rid_latest_v3?rid=...
   - Swallow timeout/NetworkError unhandled rejections (commercial-safe)
*/
(function(){
  try{
    if (window.__VSP_P3K22__) return;
    window.__VSP_P3K22__ = true;

    const usp = new URLSearchParams(location.search || "");
    const rid = (usp.get("rid") || "").trim();
    const debug = (usp.get("debug_ui") === "1");
    if (rid) window.__VSP_RID_LOCKED__ = rid;

    function softErr(x){
      const msg = String((x && (x.message || x.reason || x)) || "").toLowerCase();
      return msg.includes("timeout") || msg.includes("networkerror") || msg.includes("ns_binding_aborted");
    }

    window.addEventListener("unhandledrejection", function(e){
      try{ if (!debug && softErr(e && e.reason)) e.preventDefault(); }catch(_){}
    });
    window.addEventListener("error", function(e){
      try{ if (!debug && softErr(e && e.error)) e.preventDefault(); }catch(_){}
    });

    if (!debug && rid && typeof window.fetch === "function"){
      const _fetch = window.fetch.bind(window);
      window.fetch = function(input, init){
        try{
          const url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
          if (url && url.indexOf("/api/vsp/rid_latest") !== -1){
            const body = JSON.stringify({ok:true, rid: rid, mode:"url_rid"});
            return Promise.resolve(new Response(body, {status:200, headers:{"Content-Type":"application/json"}}));
          }
        }catch(_){}
        return _fetch(input, init);
      };
    }

    if (!debug && rid && window.XMLHttpRequest && window.XMLHttpRequest.prototype){
      const _open = window.XMLHttpRequest.prototype.open;
      window.XMLHttpRequest.prototype.open = function(method, url){
        try{
          const u = String(url || "");
          if (u.indexOf("/api/vsp/rid_latest") !== -1){
            const nu = "/api/vsp/rid_latest_v3?rid=" + encodeURIComponent(rid) + "&mode=url_rid";
            return _open.call(this, method, nu, true);
          }
        }catch(_){}
        return _open.apply(this, arguments);
      };
    }
  }catch(_){}
})();
