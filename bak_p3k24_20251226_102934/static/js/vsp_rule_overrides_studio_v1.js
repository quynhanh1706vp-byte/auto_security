
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

/* VSP_RULE_OVERRIDES_STUDIO_V1 - format/validate/save/apply (safe overlay) */
(()=> {
  if (window.__vsp_rules_studio_v1) return;
if(window.__VSP_CIO && window.__VSP_CIO.debug){ window.__vsp_rules_studio_v1 = true; }
  const toast = (window.VSP_UI && window.VSP_UI.toast) ? window.VSP_UI.toast : ()=>{};
  async function getJSON(url){
    const r=await fetch(url,{method:"GET"});
    const ct=(r.headers.get("content-type")||"");
    let data=null;
    try{ data = ct.includes("application/json") ? await r.json() : await r.text(); }
    catch(e){ data = await r.text().catch(()=> ""); }
    return {ok:r.ok, status:r.status, data};
  }
  async function postJSON(url, obj){
    const r=await fetch(url,{method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify(obj||{})});
    const ct=(r.headers.get("content-type")||"");
    let data=null;
    try{ data = ct.includes("application/json") ? await r.json() : await r.text(); }
    catch(e){ data = await r.text().catch(()=> ""); }
    return {ok:r.ok, status:r.status, data};
  }

  const EP_GET = ["/api/ui/rule_overrides_v2_get_v1","/api/ui/rule_overrides_get_v1"];
  const EP_SAVE= ["/api/ui/rule_overrides_v2_save_v1","/api/ui/rule_overrides_save_v1"];
  const EP_APPLY= ["/api/ui/rule_overrides_v2_apply_v2","/api/ui/rule_overrides_apply_v1"];

  async function firstOKGet(urls){
    for(const u of urls){
      const r=await getJSON(u);
      if(r.ok) return {url:u, ...r};
    }
    return null;
  }
  async function firstOKPost(urls, payload){
    for(const u of urls){
      const r=await postJSON(u, payload);
      if(r.ok) return {url:u, ...r};
    }
    return null;
  }

  function injectStudio(){
    if(document.getElementById("vspRulesStudio")) return;
    const host = document.body;
    const card=document.createElement("section");
    card.id="vspRulesStudio";
    card.className="vsp-card";
    card.style.margin="12px 0";
    card.innerHTML=`
      <div class="vsp-card-h">
        <div class="vsp-h1">Policy Studio</div>
        <div class="vsp-muted" style="font-size:12px;margin-top:4px;">Format • Validate • Save • Apply (v2 store)</div>
      </div>
      <div class="vsp-card-b">
        <div style="display:flex; gap:10px; flex-wrap:wrap; margin-bottom:10px;">
          <button class="vsp-btn" id="vspRulesLoad" type="button">Load</button>
          <button class="vsp-btn" id="vspRulesFormat" type="button">Format</button>
          <button class="vsp-btn" id="vspRulesValidate" type="button">Validate</button>
          <button class="vsp-btn vsp-btn-good" id="vspRulesSave" type="button">Save</button>
          <button class="vsp-btn vsp-btn-warn" id="vspRulesApply" type="button">Apply to RUN…</button>
          <input id="vspRulesRid" class="vsp-code" placeholder="RID e.g. RUN_20251120_130310"
                 style="min-width:260px; padding:10px 12px; border-radius:12px; border:1px solid rgba(255,255,255,.12); background:rgba(0,0,0,.18); color:inherit;">
          <span class="vsp-badge info" id="vspRulesMeta">—</span>
        </div>
        <textarea id="vspRulesText" spellcheck="false"
          style="width:100%; min-height:220px; padding:12px; border-radius:14px; border:1px solid rgba(255,255,255,.10);
                 background:rgba(0,0,0,.28); color:inherit; font-family:var(--mono); font-size:12px; line-height:1.35;"></textarea>
        <pre class="vsp-pre" id="vspRulesLog">Ready.</pre>
      </div>
    `;
    host.insertBefore(card, host.firstChild.nextSibling);

    const logEl=document.getElementById("vspRulesLog");
    const ta=document.getElementById("vspRulesText");
    const meta=document.getElementById("vspRulesMeta");

    const log=(m)=>{ const ts=new Date().toISOString().replace("T"," ").replace("Z",""); logEl.textContent=`[${ts}] ${m}\n`+logEl.textContent; };

    document.getElementById("vspRulesLoad").onclick=async ()=>{
      const r=await firstOKGet(EP_GET);
      if(!r){ toast("bad","Load failed","No GET endpoint"); log("Load failed: no endpoint"); return; }
      const d=r.data||{};
      ta.value = JSON.stringify(d.data || d, null, 2);
      meta.textContent = `GET: ${r.url}`;
      toast("good","Loaded",r.url);
      log(`Loaded from ${r.url}`);
    };

    document.getElementById("vspRulesFormat").onclick=()=>{
      try{
        const obj=JSON.parse(ta.value||"{}");
        ta.value=JSON.stringify(obj,null,2);
        toast("good","Formatted","JSON pretty");
        log("Format OK");
      }catch(e){
        toast("bad","Format failed","Invalid JSON");
        log("Format failed: "+e);
      }
    };

    document.getElementById("vspRulesValidate").onclick=()=>{
      try{
        const obj=JSON.parse(ta.value||"{}");
        const rules = obj.rules || (obj.data && obj.data.rules) || [];
        if(!Array.isArray(rules)) throw new Error("rules must be array");
        toast("good","Validate OK",`rules_count=${rules.length}`);
        log(`Validate OK rules_count=${rules.length}`);
      }catch(e){
        toast("bad","Validate failed",String(e));
        log("Validate failed: "+e);
      }
    };

    document.getElementById("vspRulesSave").onclick=async ()=>{
      let obj=null;
      try{ obj=JSON.parse(ta.value||"{}"); }catch(e){
        toast("bad","Save failed","Invalid JSON"); log("Save failed: invalid JSON"); return;
      }
      const payload = (obj.data && obj.data.rules) ? obj.data : obj; // accept either shape
      const r=await firstOKPost(EP_SAVE, payload);
      if(!r){ toast("bad","Save failed","No SAVE endpoint"); log("Save failed: no endpoint"); return; }
      meta.textContent = `SAVE: ${r.url}`;
      toast("good","Saved",r.url);
      log(`Saved via ${r.url}: ${JSON.stringify(r.data).slice(0,240)}`);
    };

    document.getElementById("vspRulesApply").onclick=async ()=>{
      const rid=(document.getElementById("vspRulesRid").value||"").trim();
      if(!rid){ toast("warn","Need RID","Enter RUN_..."); return; }
      const r=await firstOKPost(EP_APPLY, {rid});
      if(!r){ toast("bad","Apply failed","No APPLY endpoint"); log("Apply failed: no endpoint"); return; }
      meta.textContent = `APPLY: ${r.url}`;
      toast("good","Applied",rid);
      log(`Applied via ${r.url}: ${JSON.stringify(r.data).slice(0,320)}`);
    };
  }

  if(location.pathname==="/rule_overrides"){
    if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", injectStudio);
    else injectStudio();
  }
})();
