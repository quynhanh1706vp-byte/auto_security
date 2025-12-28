
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

/* VSP_P0_CONTAINERS_FIX_V1
   Ensures DashCommercial containers exist so dashboard doesn't warn "missing containers".
*/
(() => {
  if (window.__vsp_p0_containers_fix_v1) return;
if(window.__VSP_CIO && window.__VSP_CIO.debug){ window.__vsp_p0_containers_fix_v1 = true; }
  const IDS = ["vsp-chart-severity","vsp-chart-trend","vsp-chart-bytool","vsp-chart-topcve"];

  function ensure(){
    try{
      // Prefer legacy root first (because bundle renderer expects it),
      // otherwise use luxe host, otherwise body.
      const root =
        document.querySelector("#vsp5_root") ||
        document.querySelector("#vsp_luxe_host") ||
        document.body;

      if (!root) return;

      let shell = document.querySelector("#vsp5_dash_shell");
      if (!shell){
        shell = document.createElement("div");
        shell.id = "vsp5_dash_shell";
        // non-intrusive layout: does not break existing UI; just provides containers.
        shell.style.cssText = "padding:12px 14px; display:grid; grid-template-columns: 1fr 1fr; gap:12px;";
        // Insert near top of root so charts have stable place.
        root.prepend(shell);
      }

      for (const id of IDS){
        if (document.getElementById(id)) continue;
        const d = document.createElement("div");
        d.id = id;
        // give min height so charts have space but not too big
        d.style.cssText = "min-height:160px;";
        shell.appendChild(d);
      }
    }catch(e){}
  }

  if (document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", ensure);
  } else {
    ensure();
  }

  // In case renderer wipes DOM, re-ensure shortly after load.
  setTimeout(ensure, 800);
})();
