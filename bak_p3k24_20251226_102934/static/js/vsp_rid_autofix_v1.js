
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

/* VSP_NOOP_RID_AUTOFIX_FORCE_V2
 * Commercial Dashboard contract: rid comes ONLY from /api/vsp/rid_latest_gate_root (DashCommercialV1),
 * NEVER from this legacy rid_autofix module.
 */
(()=> {
  if (window.__vsp_noop_rid_autofix_force_v2) return;
if(window.__VSP_CIO && window.__VSP_CIO.debug){ window.__vsp_noop_rid_autofix_force_v2 = true; }
  try { console.info("[VSP] rid_autofix DISABLED (noop force v2)"); } catch(e){}
})();
