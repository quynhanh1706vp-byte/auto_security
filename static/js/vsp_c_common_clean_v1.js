
;(()=>{ 
  // VSP_P433_BOOT_FUNCTION_V1
  if (typeof window.boot === "function") return;

  const q = [];
  function run(){
    while(q.length){
      const fn = q.shift();
      try{ fn && fn(); }catch(e){ console.error("[boot]", e); }
    }
  }

  function bootFn(fn){
    if (typeof fn === "function"){
      if (document.readyState === "loading") q.push(fn);
      else { try{ fn(); }catch(e){ console.error("[boot]", e); } }
    }
    return bootFn;
  }
  bootFn.q = q;
  bootFn.run = run;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", run, { once:true });
  } else {
    setTimeout(run, 0);
  }
  window.boot = bootFn;
})(); 

/* VSP_C_COMMON_CLEAN_V1
   - Minimal, safe helpers (no override existing behavior)
   - installOnce registry to stop duplicate installers (P421-ready)
   - log wrappers
*/
(function(){
  'use strict';
  const W = window;
  W.VSP = W.VSP || {};

  // --- logging (prefix, can be silenced by setting VSP_LOG=0) ---
  const LOG_ON = (W.VSP_LOG === undefined) ? 1 : (W.VSP_LOG ? 1 : 0);
  function _pfx(){ return '[VSP]'; }
  W.VSP.log = function(){ if(!LOG_ON) return; try{ console.log(_pfx(), ...arguments); }catch(e){} };
  W.VSP.warn = function(){ if(!LOG_ON) return; try{ console.warn(_pfx(), ...arguments); }catch(e){} };
  W.VSP.err = function(){ if(!LOG_ON) return; try{ console.error(_pfx(), ...arguments); }catch(e){} };

  // --- DOM helpers (non-invasive) ---
  W.VSP.q  = W.VSP.q  || function(sel, root){ return (root||document).querySelector(sel); };
  W.VSP.qa = W.VSP.qa || function(sel, root){ return Array.prototype.slice.call((root||document).querySelectorAll(sel)); };
  W.VSP.on = W.VSP.on || function(el, ev, fn, opt){ if(el && el.addEventListener) el.addEventListener(ev, fn, opt||false); };

  // --- installOnce (idempotent) ---
  const _reg = W.VSP.__install_registry = W.VSP.__install_registry || Object.create(null);
  W.VSP.installOnce = W.VSP.installOnce || function(key, fn){
    try{
      if(_reg[key]) return false;
      _reg[key] = 1;
      fn && fn();
      return true;
    }catch(e){
      try{ W.VSP.err('installOnce failed', key, e); }catch(_) {}
      return false;
    }
  };

  // --- small utils ---
  W.VSP.nowISO = W.VSP.nowISO || function(){ try{ return new Date().toISOString(); }catch(e){ return ''; } };

  // mark loaded
  W.VSP.__c_common_clean_v1 = 1;
})();


/* VSP_P450_COMMON_SAFE_FETCH_V1 */

  // VSP_P450: minimal JSON fetch with timeout + safe error
  VSP.fetchJSON = async function(url, opts){
    opts = opts || {};
    const timeoutMs = Number(opts.timeoutMs || 3500);
    const ctl = (typeof AbortController !== "undefined") ? new AbortController() : null;
    const t = ctl ? setTimeout(() => { try{ ctl.abort(); }catch(e){} }, timeoutMs) : null;
    try{
      const r = await fetch(url, { signal: ctl ? ctl.signal : undefined, credentials: "same-origin" });
      if (!r.ok) throw new Error("HTTP " + r.status);
      return await r.json();
    } finally {
      if (t) clearTimeout(t);
    }
  };
  VSP.safe = async function(promise, fallback){
    try { return await promise; } catch(e){ return fallback; }
  };



/* VSP_P473_LOADER_SNIPPET_V1 */
(function(){
  try{
    if (window.__VSP_SIDEBAR_FRAME_V1__) return;
    if (document.getElementById("vsp_c_sidebar_v1_loader")) return;
    var s=document.createElement("script");
    s.id="vsp_c_sidebar_v1_loader";
    s.src="/static/js/vsp_c_sidebar_v1.js?v="+Date.now();
    document.head.appendChild(s);
  }catch(e){}
})();
