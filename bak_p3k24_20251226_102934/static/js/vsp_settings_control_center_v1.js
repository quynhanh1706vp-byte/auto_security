
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

/* VSP_SETTINGS_CONTROL_CENTER_V1 - health + config snapshot (safe overlay) */
(()=> {
  

/* VSP_RUNFILEALLOW_FETCH_GUARD_V3C
   - prevent 404 spam when rid missing/invalid
   - auto add default path when missing
   - covers fetch + XMLHttpRequest
*/
(()=> {
  try {
    if (window.__vsp_runfileallow_fetch_guard_v3c) return;
if(window.__VSP_CIO && window.__VSP_CIO.debug){ window.__vsp_runfileallow_fetch_guard_v3c = true; }
    function _isLikelyRid(rid){
      if(!rid || typeof rid !== "string") return false;
      if(rid.length < 6) return false;
      if(rid.includes("{") || rid.includes("}")) return false;
      return /^[A-Za-z0-9_\-]+$/.test(rid);
    }

    function _fix(url0){
      try{
        if(!url0 || typeof url0 !== "string") return {action:"pass"};
        if(!url0.includes("/api/vsp/run_file")) return {action:"pass"};
        const u = new URL(url0, window.location.origin);
        const rid = u.searchParams.get("rid") || "";
        const path = u.searchParams.get("path") || "";
        if(!_isLikelyRid(rid)) return {action:"skip"};
        if(!path){
          u.searchParams.set("path","");
          return {action:"rewrite", url: u.toString().replace(window.location.origin,"")};
        }
        return {action:"pass"};
      }catch(e){
        return {action:"pass"};
      }
    }

    // fetch
    const _origFetch = window.fetch ? window.fetch.bind(window) : null;
    if (_origFetch){
      window.fetch = function(input, init){
        try{
          const url0 = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
          const fx = _fix(url0);
          if (fx.action === "skip"){
            const body = JSON.stringify({ok:false, skipped:true, reason:"no rid"});
            return Promise.resolve(new Response(body, {status:200, headers:{"Content-Type":"application/json; charset=utf-8"}}));
          }
          if (fx.action === "rewrite"){
            if (typeof input === "string") input = fx.url;
            else input = new Request(fx.url, input);
          }
        }catch(e){}
        return _origFetch(input, init);
      };
    }

    // XHR
    const XHR = window.XMLHttpRequest;
    if (XHR && XHR.prototype && XHR.prototype.open){
      const _open = XHR.prototype.open;
      XHR.prototype.open = function(method, url, async, user, password){
        try{
          const url0 = (typeof url === "string") ? url : "";
          const fx = _fix(url0);
          if (fx.action === "skip"){
            const body = encodeURIComponent(JSON.stringify({ok:false, skipped:true, reason:"no rid"}));
            url = "data:application/json;charset=utf-8," + body;
          } else if (fx.action === "rewrite"){
            url = fx.url;
          }
        }catch(e){}
        return _open.call(this, method, url, async, user, password);
      };
    }
  } catch(e) {}
})();

if (window.__vsp_settings_cc_v1) return;
if(window.__VSP_CIO && window.__VSP_CIO.debug){ window.__vsp_settings_cc_v1 = true; }
  const toast = (window.VSP_UI && window.VSP_UI.toast) ? window.VSP_UI.toast : ()=>{};
  async function getJSON(url){
    const r=await fetch(url,{method:"GET"});
    const ct=(r.headers.get("content-type")||"");
    let data=null;
    try{ data = ct.includes("application/json") ? await r.json() : await r.text(); }
    catch(e){ data = await r.text().catch(()=> ""); }
    return {ok:r.ok, status:r.status, data};
  }

  function inject(){
    if(document.getElementById("vspSettingsCC")) return;
    const card=document.createElement("section");
    card.id="vspSettingsCC";
    card.className="vsp-card";
    card.style.margin="12px 0";
    card.innerHTML=`
      <div class="vsp-card-h">
        <div class="vsp-h1">Control Center</div>
        <div class="vsp-muted" style="font-size:12px;margin-top:4px;">Quick health + last run + overrides store snapshot.</div>
      </div>
      <div class="vsp-card-b">
        <div class="vsp-kv"><span class="vsp-muted">Last run</span><span class="vsp-code" id="vspSetLastRun">—</span></div>
        <div class="vsp-kv"><span class="vsp-muted">KICS timeout</span><span class="vsp-code" id="vspSetKics">env KICS_TIMEOUT_SEC</span></div>
        <div class="vsp-kv"><span class="vsp-muted">Overrides store</span><span class="vsp-code" id="vspSetStore">—</span></div>
        <div style="display:flex; gap:10px; flex-wrap:wrap; margin-top:10px;">
          <button class="vsp-btn" id="vspSetProbe" type="button">Probe</button>
          <button class="vsp-btn vsp-btn-primary" id="vspSetOpenRuns" type="button">Open Runs</button>
        </div>
        <pre class="vsp-pre" id="vspSetLog">Ready.</pre>
      </div>
    `;
    document.body.insertBefore(card, document.body.firstChild.nextSibling);

    const logEl=document.getElementById("vspSetLog");
    const log=(m)=>{ const ts=new Date().toISOString().replace("T"," ").replace("Z",""); logEl.textContent=`[${ts}] ${m}\n`+logEl.textContent; };

    document.getElementById("vspSetOpenRuns").onclick=()=> location.href="/runs";

    document.getElementById("vspSetProbe").onclick=async ()=>{
      const runs=await getJSON("/api/vsp/rid_latest_v3");
      if(runs.ok && runs.data && runs.data.items && runs.data.items[0]){
        const it=runs.data.items[0];
        const rid=it.rid || it.run_id || it.id || "—";
        document.getElementById("vspSetLastRun").textContent = rid;
        log("runs ok rid="+rid);
      }else{
        log("runs probe fail HTTP "+runs.status);
        toast("warn","Runs probe failed",String(runs.status));
      }
      // overrides store best-effort
      const eps=["/api/ui/rule_overrides_v2_get_v1","/api/ui/rule_overrides_get_v1"];
      let store="—";
      for(const u of eps){
        const r=await getJSON(u);
        if(r.ok && r.data && typeof r.data==="object"){
          store = r.data.store || store;
          log("overrides ok via "+u);
          break;
        }
      }
      document.getElementById("vspSetStore").textContent = store;
    };
  }

  if(location.pathname==="/settings"){
    if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", inject);
    else inject();
  }
})();
