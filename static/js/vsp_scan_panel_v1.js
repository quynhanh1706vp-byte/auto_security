
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

/* VSP_P1_SCAN_PANEL_V1 - commercial-safe scan trigger + status poll */
(()=> {
  if (window.__vsp_scan_panel_v1) return;
if(window.__VSP_CIO && window.__VSP_CIO.debug){ window.__vsp_scan_panel_v1 = true; }
  const $ = (id)=> document.getElementById(id);

  function log(msg){
    const el = $("vspScanLog");
    if(!el) return;
    const ts = new Date().toISOString().replace('T',' ').replace('Z','');
    el.textContent = `[${ts}] ${msg}\n` + el.textContent;
  }

  async function postJSON(url, obj){
    const r = await fetch(url, {
      method: "POST",
      headers: {"Content-Type":"application/json"},
      body: JSON.stringify(obj || {})
    });
    const ct = (r.headers.get("content-type")||"");
    let data = null;
    try{
      data = ct.includes("application/json") ? await r.json() : await r.text();
    }catch(e){
      data = await r.text().catch(()=> "");
    }
    return {ok: r.ok, status: r.status, data};
  }

  async function getJSON(url){
    const r = await fetch(url, {method:"GET"});
    const ct = (r.headers.get("content-type")||"");
    let data = null;
    try{
      data = ct.includes("application/json") ? await r.json() : await r.text();
    }catch(e){
      data = await r.text().catch(()=> "");
    }
    return {ok: r.ok, status: r.status, data};
  }

  function pickReqId(resp){
    if(!resp) return null;
    const d = resp.data;
    if(!d || typeof d !== "object") return null;
    return d.req_id || d.request_id || d.id || d.rid || null;
  }

  async function pollStatus(reqId, urlOverride){
    // If backend uses req_id, poll; if only rid returned, we still try (won't break).
    const url = urlOverride || `/api/vsp/run_status_v1/${encodeURIComponent(reqId)}`;
    for(let i=0;i<90;i++){
      const r = await getJSON(url);
      if(!r.ok){
        log(`status poll: HTTP ${r.status} (endpoint may not exist for id=${reqId}).`);
        return;
      }
      const d = r.data;
      log(`status: ${JSON.stringify(d).slice(0,240)}${JSON.stringify(d).length>240?"...":""}`);
      // heuristic stop
      if(d && typeof d === "object"){
        const st = (d.status || d.state || d.overall || "").toString().toUpperCase();
        if(["DONE","FINISHED","OK","PASS","FAIL","ERROR","GREEN","AMBER","RED"].includes(st)) return;
        if(d.done === true) return;
      }
      await new Promise(res=>setTimeout(res, 2000));
    }
    log("status poll: timeout (still running?)");
  }

  async function startScan(){
    const target = ($("vspScanTarget")?.value || "").trim();
    const mode = ($("vspScanMode")?.value || "FULL").trim();
    const note = ($("vspScanNote")?.value || "").trim();

    if(!target){
      log("missing target path.");
      return;
    }

    const payload = {
      target_path: target,
      mode: mode,
      note: note,
      source: "UI_SCAN_PANEL_V1"
    };

    log(`POST /api/vsp/run_v1 => ${JSON.stringify(payload)}`);
    const r = await postJSON("/api/vsp/run_v1", payload);

    if(!r.ok){
      log(`run_v1 failed: HTTP ${r.status}. Response: ${typeof r.data==="string"?r.data:JSON.stringify(r.data)}`);
      log("Hint: backend may not wire run_v1 yet, or expects different fields.");
      return;
    }

    log(`run_v1 ok: ${typeof r.data==="string"?r.data:JSON.stringify(r.data)}`);

    const d = r && r.data && typeof r.data==="object" ? r.data : null;
    const statusUrl = d && (d.status_url || d.statusUrl) ? (d.status_url || d.statusUrl) : null;
    const reqId = pickReqId(r);
    if(reqId){
      log(`polling status for id=${reqId}`);
      await pollStatus(reqId, statusUrl);
    }else{
      log("No req_id in response; cannot poll. (Still OK — backend contract may differ.)");
    }
  }

  function wire(){
    const startBtn = $("vspScanStartBtn");
    const refBtn = $("vspScanRefreshBtn");
    if(startBtn){
      startBtn.addEventListener("click", ()=> startScan().catch(e=>log("startScan error: "+e)));
    }
    if(refBtn){
      refBtn.addEventListener("click", ()=> location.reload());
    }
  }

  if (document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", wire);
  } else {
    wire();
  }
})();
