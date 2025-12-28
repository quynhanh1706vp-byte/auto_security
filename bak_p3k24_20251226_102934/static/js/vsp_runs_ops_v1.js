
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

/* VSP_RUNS_OPS_V1 - live scan card + export buttons */
(()=> {
  if (window.__vsp_runs_ops_v1) return;
if(window.__VSP_CIO && window.__VSP_CIO.debug){ window.__vsp_runs_ops_v1 = true; }
  const {toast, getJSON} = window.VSP_UI || {toast:()=>{}, getJSON: async()=>({ok:false})};

  function $(id){ return document.getElementById(id); }
  function el(tag, cls){ const e=document.createElement(tag); if(cls) e.className=cls; return e; }

  async function postJSON(url, obj){
    const r=await fetch(url,{method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify(obj||{})});
    const ct=(r.headers.get("content-type")||"");
    let data=null;
    try{ data = ct.includes("application/json") ? await r.json() : await r.text(); }
    catch(e){ data = await r.text().catch(()=> ""); }
    return {ok:r.ok, status:r.status, data};
  }

  function injectOpsCard(){
    if(document.getElementById("vspOpsCard")) return;

    const host = document.querySelector("#vspScanPanel") || document.body;
    const card = el("section","vsp-card");
    card.id="vspOpsCard";
    card.style.margin="14px 0";
    card.innerHTML = `
      <div class="vsp-card-h">
        <div class="vsp-h1">Run Console</div>
        <div class="vsp-muted" style="font-size:12px;margin-top:4px;">
          Live status + 1-click exports (ZIP/PDF/HTML). KICS timeout/degraded supported.
        </div>
      </div>
      <div class="vsp-card-b">
        <div class="vsp-kv"><span class="vsp-muted">REQ_ID</span><span class="vsp-code" id="vspReqId">—</span></div>
        <div class="vsp-kv"><span class="vsp-muted">Stage</span><span class="vsp-code" id="vspStage">—</span></div>
        <div class="vsp-kv"><span class="vsp-muted">Progress</span><span class="vsp-code" id="vspPct">—</span></div>
        <div class="vsp-progress" style="margin:10px 0 12px;"><i id="vspBar"></i></div>
        <div style="display:flex; gap:10px; flex-wrap:wrap;">
          <button class="vsp-btn vsp-btn-good" id="vspBtnStart" type="button">Start scan (FAST)</button>
          <button class="vsp-btn" id="vspBtnPoll" type="button">Poll status</button>
          <button class="vsp-btn vsp-btn-primary" id="vspBtnZip" type="button" disabled>Download ZIP</button>
          <button class="vsp-btn vsp-btn-primary" id="vspBtnPdf" type="button" disabled>Download PDF</button>
          <button class="vsp-btn" id="vspBtnHtml" type="button" disabled>Open HTML report</button>
        </div>
        <pre class="vsp-pre" id="vspOpsLog">Ready.</pre>
      </div>
    `;
    host.parentNode.insertBefore(card, host);

    function log(msg){
      const p=$("#vspOpsLog");
      const ts=new Date().toISOString().replace("T"," ").replace("Z","");
      p.textContent = `[${ts}] ${msg}\n` + p.textContent;
    }

    let curReq=null;
    let statusUrl=null;
    let ridGuess=null;

    async function poll(){
      if(!curReq){
        toast("warn","No REQ_ID","Start scan or set req_id first.");
        return;
      }
      const url = statusUrl || `/api/vsp/run_status_v1/${encodeURIComponent(curReq)}`;
      const r = await getJSON(url);
      if(!r.ok){
        log(`poll failed: HTTP ${r.status}`);
        return;
      }
      const d=r.data||{};
      const st=(d.stage_name||d.stage||"—");
      const pct=(d.progress_pct!=null?d.progress_pct:"—");
      $("#vspStage").textContent=st;
      $("#vspPct").textContent=String(pct);
      const bar=$("#vspBar");
      const n = Number(pct);
      if(Number.isFinite(n)) bar.style.width = Math.max(0,Math.min(100,n))+"%";

      // guess rid/run_dir
      ridGuess = d.rid || d.run_id || d.latest_rid || ridGuess;
      const rd = d.run_dir || d.ci_run_dir || "";
      log(`status: stage="${st}" pct=${pct} rid=${ridGuess||"?"} dir=${rd}`);

      // enable exports if rid known
      if(ridGuess){
        $("#vspBtnZip").disabled=false;
        $("#vspBtnPdf").disabled=false;
        $("#vspBtnHtml").disabled=false;
      }
    }

    async function startFast(){
      const payload = { target_path:"/home/test/Data/SECURITY_BUNDLE", mode:"FAST", note:"ui-runs-ops-fast" };
      log(`POST /api/vsp/run_v1 ${JSON.stringify(payload)}`);
      const r = await postJSON("/api/vsp/run_v1", payload);
      if(!r.ok){
        log(`start failed: HTTP ${r.status} ${typeof r.data==="string"?r.data:JSON.stringify(r.data)}`);
        toast("bad","Start scan failed",`HTTP ${r.status}`);
        return;
      }
      const d=r.data||{};
      curReq = d.req_id || d.request_id || d.id || null;
      statusUrl = d.status_url || d.statusUrl || null;
      $("#vspReqId").textContent = curReq || "—";
      log(`started ok: req_id=${curReq} status_url=${statusUrl||"(default)"}`);
      toast("good","Scan started",curReq||"");
      await poll();
      // auto poll loop (light)
      for(let i=0;i<60;i++){
        await new Promise(res=>setTimeout(res, 2000));
        await poll();
        // stop if final
        const txt=$("#vspStage").textContent||"";
        if(String(txt).toUpperCase().includes("DONE") || String(txt).toUpperCase().includes("FINISH")) break;
      }
    }

    $("#vspBtnStart").onclick=()=> startFast().catch(e=>log("start error: "+e));
    $("#vspBtnPoll").onclick=()=> poll().catch(e=>log("poll error: "+e));

    $("#vspBtnZip").onclick=()=>{
      if(!ridGuess) return;
      location.href = `/api/vsp/run_export_zip?rid=${encodeURIComponent(ridGuess)}`;
    };
    $("#vspBtnPdf").onclick=()=>{
      if(!ridGuess) return;
      location.href = `/api/vsp/run_export_pdf?rid=${encodeURIComponent(ridGuess)}`;
    };
    $("#vspBtnHtml").onclick=async ()=>{
      if(!ridGuess) return;
      // best-effort: open index.html if exported in reports
      toast("info","Tip","If HTML exists in ZIP, open reports/index.html from run_dir on server.");
    };

    // initial probe last run
    (async ()=>{
      const r=await getJSON("/api/vsp/rid_latest_v3");
      if(r.ok && r.data && r.data.items && r.data.items[0]){
        const it=r.data.items[0];
        ridGuess = it.rid || it.run_id || it.id || null;
        if(ridGuess){
          $("#vspBtnZip").disabled=false;
          $("#vspBtnPdf").disabled=false;
          $("#vspBtnHtml").disabled=false;
          log(`last run detected: rid=${ridGuess}`);
        }
      }
    })().catch(()=>{});
  }

  if(location.pathname==="/runs"){
    if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", injectOpsCard);
    else injectOpsCard();
  }
})();
