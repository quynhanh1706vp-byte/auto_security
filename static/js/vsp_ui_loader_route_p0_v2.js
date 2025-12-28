
// __VSP_CIO_HELPER_V1
(function(){
  try{
    window.__VSP_CIO = window.__VSP_CIO || {};
    const qs = new URLSearchParams(location.search);
    window.__VSP_CIO.debug = (qs.get("debug")==="1") || (localStorage.getItem("VSP_DEBUG")==="1");
    window.__VSP_CIO.visible = function(){ return document.visibilityState === "visible"; };
    window.__VSP_CIO.sleep = (ms)=>new Promise(r=>setTimeout(r, ms));
    window.__VSP_CIO.backoff = async function(fn, opt){
      opt = opt || {};
      let delay = opt.delay || 800;
      const maxDelay = opt.maxDelay || 8000;
      const maxTries = opt.maxTries || 6;
      for(let i=0;i<maxTries;i++){
        if(!window.__VSP_CIO.visible()){
          await window.__VSP_CIO.sleep(600);
          continue;
        }
        try { return await fn(); }
        catch(e){
          if(window.__VSP_CIO.debug) console.warn("[VSP] backoff retry", i+1, e);
          await window.__VSP_CIO.sleep(delay);
          delay = Math.min(maxDelay, delay*2);
        }
      }
      throw new Error("backoff_exhausted");
    };
    window.__VSP_CIO.api = {
      ridLatest: ()=>"/api/vsp/rid_latest_v3",
      runs: (limit,offset)=>`/api/vsp/runs_v3?limit=${limit||50}&offset=${offset||0}`,
      gate: (rid)=>`/api/vsp/run_gate_v3?rid=${encodeURIComponent(rid||"")}`,
      findingsPage: (rid,limit,offset)=>`/api/vsp/findings_v3?rid=${encodeURIComponent(rid||"")}&limit=${limit||100}&offset=${offset||0}`,
      artifact: (rid,kind,download)=>`/api/vsp/artifact_v3?rid=${encodeURIComponent(rid||"")}&kind=${encodeURIComponent(kind||"")}${download?"&download=1":""}`
    };
  }catch(_){}
})();

/* VSP_UI_LOADER_ROUTE_P0_V2: route-scoped loader that never blocks UI */
(function(){
  'use strict';

/* __VSP_DD_SAFE_CALL__ (P0): call handler as fn OR {open: fn} */
(function(){
  'use strict';
  if (window.__VSP_DD_SAFE_CALL__) return;
  window.__VSP_DD_SAFE_CALL__ = function(handler){
    try{
      var args = Array.prototype.slice.call(arguments, 1);
      if (typeof handler === 'function') return handler.apply(null, args);
      if (handler && typeof handler.open === 'function') return handler.open.apply(handler, args);
    } catch(e){
      try{ console.warn('[VSP][DD_SAFE_CALL]', e); } catch(_){}
    }
    return null;
  };
})();


  if (window.__VSP_UI_LOADER_ROUTE_P0_V2) return;
  window.__VSP_UI_LOADER_ROUTE_P0_V2 = 1;

  const log = (...a)=>{ try{ console.log("[VSP_LOADER_P0_V2]", ...a); } catch(_){} };
  const warn = (...a)=>{ try{ console.warn("[VSP_LOADER_P0_V2]", ...a); } catch(_){} };

  const loaded = new Map(); // url -> Promise<{ok:boolean}>
  function injectScript(url){
    if (loaded.has(url)) return loaded.get(url);
    const p = new Promise((resolve)=>{
      try{
        const s = document.createElement("script");
        s.src = url;
        s.async = true;
        s.crossOrigin = "anonymous";
        let done = false;
        const finish = (ok, why)=>{
          if (done) return;
          done = true;
          if (!ok) warn("script failed/degraded:", url, why||"");
          resolve({ok: !!ok});
        };
        s.onload = ()=>finish(true);
        s.onerror = ()=>finish(false, "onerror");
        // HARD fail-safe: never hang waiting for onload
        setTimeout(()=>finish(false, "timeout"), 4000);
        (document.head || document.documentElement).appendChild(s);
      } catch(e){
        warn("inject exception:", url, e);
        resolve({ok:false});
      }
    });
    loaded.set(url, p);
    return p;
  }

  function featOn(key){
    try{
      const f = window.VSP_UI_FEATURES_V1 || window.__VSP_UI_FEATURES_V1 || null;
      if (!f) return true; // default ON if missing
      if (typeof f === "function") return !!f(key);
      if (typeof f === "object") return !!f[key];
    } catch(_){}
    return true;
  }

  const ROUTE_SCRIPTS = {
    dashboard: [
      "/static/js/vsp_dashboard_enhance_v1.js",
      "/static/js/vsp_dashboard_charts_pretty_v3.js",
      "/static/js/vsp_degraded_panel_hook_v3.js"
    ],
    runs: ["/static/js/vsp_runs_tab_resolved_v1.js"],
    datasource: ["/static/js/vsp_datasource_tab_v1.js"],
    settings: ["/static/js/vsp_settings_tab_v1.js"],
    rules: ["/static/js/vsp_rule_overrides_tab_v1.js"],
  };

  function normRoute(){
    const h = (location.hash || "").replace(/^#/, "");
    const r = (h.split("&")[0] || "").trim().toLowerCase();
    if (!r) return "dashboard";
    if (r === "artifacts") return "datasource";
    return r;
  }

  async function applyRoute(){
    const r = normRoute();
    const scripts = ROUTE_SCRIPTS[r] || [];
    log("route=", r, "scripts=", scripts);

    // feature gates (matching your toggles)
    if (r === "dashboard" && !featOn("DASHBOARD_CHARTS")) return;
    if (r === "runs" && !featOn("RUNS_PANEL")) return;
    if (r === "datasource" && !featOn("DATASOURCE_TAB")) return;
    if (r === "settings" && !featOn("SETTINGS_TAB")) return;
    if (r === "rules" && !featOn("RULE_OVERRIDES_TAB")) return;

    // load in-order but never block forever
    for (const u of scripts) {
      // add cache-buster that changes on each hard refresh anyway; keep stable per page load
      const url = u + (u.includes("?") ? "&" : "?") + "v=" + (window.__VSP_LOADER_CB || (window.__VSP_LOADER_CB = Date.now()));
      await injectScript(url);
    }

    try{
      // Some modules may expose a markStable; call if exists
      if (typeof window.__vsp_markStable === "function") window.__vsp_markStable();
    } catch(_){}
  }

  window.addEventListener("hashchange", ()=>{ applyRoute(); });
  // initial
  setTimeout(()=>applyRoute(), 0);
})();
