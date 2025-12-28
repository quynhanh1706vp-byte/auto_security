
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

/* VSP_DATASOURCE_EXPLORER_V1 - client-side filter bar (safe) */
(()=> {
  if (window.__vsp_ds_explorer_v1) return;
if(window.__VSP_CIO && window.__VSP_CIO.debug){ window.__vsp_ds_explorer_v1 = true; }
  function el(tag, cls){ const e=document.createElement(tag); if(cls) e.className=cls; return e; }
  function qs(sel){ return document.querySelector(sel); }
  function qsa(sel){ return Array.from(document.querySelectorAll(sel)); }

  function injectBar(){
    if(document.getElementById("vspDsBar")) return;
    const bar = el("div","vsp-card");
    bar.id="vspDsBar";
    bar.style.margin="12px 0";
    bar.innerHTML = `
      <div class="vsp-card-h">
        <div class="vsp-h1">Findings Explorer</div>
        <div class="vsp-muted" style="font-size:12px;margin-top:4px;">Quick filter/search on the current table (safe overlay).</div>
      </div>
      <div class="vsp-card-b" style="display:flex; gap:10px; flex-wrap:wrap; align-items:center;">
        <input id="vspDsQ" placeholder="search text (rule_id, file, title...)" class="vsp-code"
               style="flex:1; min-width:260px; padding:10px 12px; border-radius:12px; border:1px solid rgba(255,255,255,.12); background:rgba(0,0,0,.18); color:inherit;">
        <select id="vspDsSev" class="vsp-code" style="padding:10px 12px; border-radius:12px; border:1px solid rgba(255,255,255,.12); background:rgba(0,0,0,.18); color:inherit;">
          <option value="">severity: ALL</option>
          <option>CRITICAL</option><option>HIGH</option><option>MEDIUM</option><option>LOW</option><option>INFO</option><option>TRACE</option>
        </select>
        <button class="vsp-btn" id="vspDsReset" type="button">Reset</button>
        <span class="vsp-badge info" id="vspDsCount">—</span>
      </div>
    `;
    const host = document.body;
    host.insertBefore(bar, host.firstChild.nextSibling);

    function apply(){
      const q=(document.getElementById("vspDsQ").value||"").toLowerCase().trim();
      const sev=(document.getElementById("vspDsSev").value||"").toUpperCase().trim();
      const rows = qsa("table tbody tr");
      let shown=0;
      rows.forEach(tr=>{
        const txt=(tr.innerText||"").toLowerCase();
        const okq = !q || txt.includes(q);
        const oksev = !sev || txt.includes(sev.toLowerCase());
        const ok = okq && oksev;
        tr.style.display = ok ? "" : "none";
        if(ok) shown++;
      });
      document.getElementById("vspDsCount").textContent = `rows: ${shown}`;
    }

    document.getElementById("vspDsQ").addEventListener("input", ()=> apply());
    document.getElementById("vspDsSev").addEventListener("change", ()=> apply());
    document.getElementById("vspDsReset").onclick=()=>{
      document.getElementById("vspDsQ").value="";
      document.getElementById("vspDsSev").value="";
      apply();
    };

    setTimeout(apply, 800);
  }

  if(location.pathname==="/data_source"){
    if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", injectBar);
    else injectBar();
  }
})();
