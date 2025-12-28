
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

/* VSP_P0_RUNS_GUARD_FINAL_V1 */
(()=> {
  if (window.__vsp_p0_runs_guard_final_v1) return;
if(window.__VSP_CIO && window.__VSP_CIO.debug){ window.__vsp_p0_runs_guard_final_v1 = true; }
  const STATE = window.__vsp_runs_guard_state_v1 = window.__vsp_runs_guard_state_v1 || {
    lastOkAt: 0,
    lastOk: null,
    inflight: null,
    lastErrAt: 0,
    lastErr: ""
  };

  function _now(){ return Date.now(); }

  function _asArray(x){ return Array.isArray(x) ? x : []; }

  async function _xhrJson(url, timeoutMs){
    return await new Promise((resolve, reject)=>{
      try{
        const xhr = new XMLHttpRequest();
        xhr.open("GET", url, true);
        xhr.responseType = "text";
        xhr.timeout = Math.max(1000, timeoutMs||5000);
        xhr.onload = ()=> {
          try{
            const t = xhr.responseText || "";
            const obj = t ? JSON.parse(t) : {};
            resolve(obj);
          }catch(e){ reject(e); }
        };
        xhr.onerror = ()=> reject(new Error("xhr error"));
        xhr.ontimeout = ()=> reject(new Error("xhr timeout"));
        xhr.send(null);
      }catch(e){ reject(e); }
    });
  }

  async function fetchJson(url, timeoutMs){
    // de-dup inflight for runs endpoint
    if (STATE.inflight) return STATE.inflight;

    const p = (async()=>{
      try{
        let obj = null;

        // prefer native fetch if usable
        if (typeof window.fetch === "function"){
          const ctrl = (typeof AbortController !== "undefined") ? new AbortController() : null;
          const to = setTimeout(()=>{ try{ ctrl && ctrl.abort(); }catch(_){ } }, Math.max(1000, timeoutMs||5000));
          try{
            const r = await window.fetch(url, {method:"GET", cache:"no-store", credentials:"same-origin", signal: ctrl?ctrl.signal:undefined});
            if (!r || !r.ok) throw new Error("fetch not ok");
            obj = await r.json();
          } finally {
            clearTimeout(to);
          }
        }

        if (!obj) obj = await _xhrJson(url, timeoutMs||5000);

        // normalize
        if (!obj || typeof obj !== "object") obj = {ok:false};
        if (obj.ok !== true) {
          // treat as error, but still allow fallback to lastOk
          throw new Error("runs payload ok!=true");
        }
        obj.items = _asArray(obj.items);
        STATE.lastOkAt = _now();
        STATE.lastOk = obj;
        return obj;
      } catch(e){
        STATE.lastErrAt = _now();
        STATE.lastErr = String(e && e.message ? e.message : e);

        // FALLBACK: if we have lastOk within 5 minutes, return it to stop flicker/crash
        if (STATE.lastOk && (_now() - STATE.lastOkAt) < 5*60*1000){
          const clone = Object.assign({}, STATE.lastOk);
          clone._degraded = true;
          clone._degraded_reason = STATE.lastErr;
          return clone;
        }
        // last resort: stable empty ok response so UI never crashes
        return {ok:true, items:[], _degraded:true, _degraded_reason: STATE.lastErr};
      } finally {
        STATE.inflight = null;
      }
    })();

    STATE.inflight = p;
    return p;
  }

  window.VSP_RUNS_GUARD = window.VSP_RUNS_GUARD || {};
  window.VSP_RUNS_GUARD.fetchJson = fetchJson;

  console.log("[VSP][P0] runs guard final enabled (no fetch lock).");
})();
