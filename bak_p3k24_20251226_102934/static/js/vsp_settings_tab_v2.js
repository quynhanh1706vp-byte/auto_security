
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


/* VSP_TABS3_V2 Settings */
(() => {
  if(window.__vsp_settings_v2) return; window.__vsp_settings_v2=true;
  const { $, esc, api, ensure } = window.__vsp_tabs3_v2 || {};
  if(!ensure) return;

  async function boot(){
    ensure();
    const root = document.getElementById("vsp_tab_root");
    if(!root) return;
    root.innerHTML = `
      <div class="vsp-row" style="justify-content:space-between;margin-bottom:10px">
        <div>
          <div style="font-size:18px;font-weight:800">Settings</div>
          <div class="vsp-muted" style="font-size:12px;margin-top:2px">UI settings JSON (v2) · GET/POST</div>
        </div>
        <div class="vsp-row">
          <button class="vsp-btn" id="st_reload">Reload</button>
          <button class="vsp-btn" id="st_save">Save</button>
        </div>
      </div>
      <div class="vsp-card" style="margin-bottom:10px">
        <div class="vsp-muted" id="st_meta" style="font-size:12px"></div>
      </div>
      <div class="vsp-card">
        <textarea id="st_text" class="vsp-code" spellcheck="false"></textarea>
        <div id="st_msg" style="margin-top:8px;font-size:12px"></div>
      </div>
    `;

    const meta=$("#st_meta"), txt=$("#st_text"), msg=$("#st_msg");

    async function load(){
      msg.innerHTML = `<span class="vsp-muted">Loading...</span>`;
      const j = await api("/api/vsp/ui_settings_v2");
      meta.textContent = `path: ${j.path||""}`;
      txt.value = JSON.stringify(j.settings||{}, null, 2);
      msg.innerHTML = `<span class="vsp-ok">OK</span>`;
    }

    async function save(){
      let obj;
      try{ obj = JSON.parse(txt.value||"{}"); }
      catch(e){ msg.innerHTML = `<span class="vsp-err">Invalid JSON:</span> ${esc(e.message||String(e))}`; return; }
      msg.innerHTML = `<span class="vsp-muted">Saving...</span>`;
      const j = await api("/api/vsp/ui_settings_v2", {method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify({settings:obj})});
      msg.innerHTML = `<span class="vsp-ok">Saved</span> · ${esc(j.path||"")}`;
    }

    $("#st_reload").onclick = ()=>load().catch(e=>msg.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`);
    $("#st_save").onclick = ()=>save().catch(e=>msg.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`);

    await load();
  }

  document.addEventListener("DOMContentLoaded", boot);
})();
