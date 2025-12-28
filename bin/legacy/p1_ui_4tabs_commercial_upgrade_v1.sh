#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# ---------- write shared CSS/JS ----------
mkdir -p static/css static/js

cat > static/css/vsp_ui_shell_v1.css <<'CSS'
/* VSP_UI_SHELL_V1 - commercial overlay */
:root{
  --bg:#070e1a; --panel:rgba(255,255,255,.04); --panel2:rgba(0,0,0,.22);
  --bd:rgba(255,255,255,.10); --bd2:rgba(255,255,255,.14);
  --txt:#d9e2ff; --muted:rgba(217,226,255,.70);
  --good:#2fe39a; --warn:#ffcc66; --bad:#ff5c7a; --info:#6aa6ff;
  --shadow: 0 12px 40px rgba(0,0,0,.35);
  --r14:14px; --r18:18px;
  --mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
  --sans: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, "Apple Color Emoji","Segoe UI Emoji";
}
html,body{background:var(--bg) !important; color:var(--txt) !important; font-family:var(--sans) !important;}
.vsp-shell-pad{padding-top:58px !important;}
.vsp-topbar{
  position:fixed; top:0; left:0; right:0; height:58px; z-index:9999;
  display:flex; align-items:center; justify-content:space-between; gap:10px;
  padding:0 14px;
  background:linear-gradient(180deg, rgba(7,14,26,.96), rgba(7,14,26,.88));
  border-bottom:1px solid var(--bd);
  box-shadow: var(--shadow);
  backdrop-filter: blur(10px);
}
.vsp-brand{display:flex; align-items:center; gap:10px; min-width:240px;}
.vsp-dot{width:10px;height:10px;border-radius:99px;background:var(--info);box-shadow:0 0 18px rgba(106,166,255,.45);}
.vsp-title{font-weight:800; letter-spacing:.2px; font-size:14px;}
.vsp-sub{font-size:12px; opacity:.72; margin-top:2px;}
.vsp-actions{display:flex; align-items:center; gap:10px; flex-wrap:wrap;}
.vsp-pill{
  display:inline-flex; align-items:center; gap:8px;
  padding:8px 10px; border-radius:999px;
  border:1px solid var(--bd); background:rgba(255,255,255,.03);
  font-size:12px; color:var(--txt);
}
.vsp-pill b{font-weight:800;}
.vsp-btn{
  cursor:pointer; user-select:none;
  display:inline-flex; align-items:center; justify-content:center; gap:8px;
  padding:8px 12px; border-radius:12px;
  border:1px solid var(--bd2); background:rgba(255,255,255,.04);
  color:var(--txt); font-size:12px; font-weight:700;
}
.vsp-btn:hover{border-color:rgba(255,255,255,.24); transform: translateY(-1px);}
.vsp-btn:active{transform: translateY(0px);}
.vsp-btn-primary{background:rgba(106,166,255,.14); border-color:rgba(106,166,255,.45);}
.vsp-btn-good{background:rgba(47,227,154,.12); border-color:rgba(47,227,154,.45);}
.vsp-btn-warn{background:rgba(255,204,102,.12); border-color:rgba(255,204,102,.45);}
.vsp-btn-bad{background:rgba(255,92,122,.12); border-color:rgba(255,92,122,.45);}

.vsp-card{
  border:1px solid var(--bd);
  background:linear-gradient(180deg, rgba(255,255,255,.045), rgba(0,0,0,.20));
  border-radius:var(--r18);
  box-shadow: var(--shadow);
}
.vsp-card-h{padding:14px 14px 10px;}
.vsp-card-b{padding:0 14px 14px;}
.vsp-h1{font-size:14px; font-weight:900; letter-spacing:.2px;}
.vsp-muted{color:var(--muted);}
.vsp-kv{display:flex; align-items:center; justify-content:space-between; gap:10px; font-size:12px; padding:8px 0; border-top:1px dashed rgba(255,255,255,.10);}
.vsp-kv:first-child{border-top:none;}
.vsp-code{font-family:var(--mono); font-size:12px; color:rgba(217,226,255,.85);}
.vsp-pre{
  background:rgba(0,0,0,.28); border:1px solid rgba(255,255,255,.08);
  border-radius:var(--r14); padding:12px; font-size:12px; line-height:1.35; overflow:auto; max-height:260px;
}
.vsp-progress{height:10px; background:rgba(255,255,255,.08); border:1px solid rgba(255,255,255,.10); border-radius:999px; overflow:hidden;}
.vsp-progress > i{display:block; height:100%; width:0%; background:rgba(106,166,255,.55);}
.vsp-badge{display:inline-flex; align-items:center; gap:6px; padding:4px 8px; border-radius:999px; font-size:12px; border:1px solid var(--bd); background:rgba(255,255,255,.03);}
.vsp-badge.good{border-color:rgba(47,227,154,.45); background:rgba(47,227,154,.10);}
.vsp-badge.warn{border-color:rgba(255,204,102,.45); background:rgba(255,204,102,.10);}
.vsp-badge.bad{border-color:rgba(255,92,122,.45); background:rgba(255,92,122,.10);}
.vsp-badge.info{border-color:rgba(106,166,255,.45); background:rgba(106,166,255,.10);}

.vsp-toast{
  position:fixed; right:14px; bottom:14px; z-index:99999;
  display:flex; flex-direction:column; gap:8px;
}
.vsp-toast .t{
  min-width: 280px; max-width: 420px;
  padding:10px 12px; border-radius:14px;
  border:1px solid var(--bd); background:rgba(0,0,0,.50);
  box-shadow: var(--shadow); font-size:12px;
}
.vsp-toast .t b{font-weight:900;}
CSS

cat > static/js/vsp_ui_shell_v1.js <<'JS'
/* VSP_UI_SHELL_V1 - topbar + toast + helpers */
(()=> {
  if (window.__vsp_ui_shell_v1) return;
  window.__vsp_ui_shell_v1 = true;

  const page = location.pathname || "/";
  const base = "";

  function el(tag, attrs={}, children=[]){
    const e=document.createElement(tag);
    for(const [k,v] of Object.entries(attrs||{})){
      if(k==="class") e.className=v;
      else if(k==="html") e.innerHTML=v;
      else e.setAttribute(k, v);
    }
    for(const c of (children||[])){
      if(typeof c==="string") e.appendChild(document.createTextNode(c));
      else if(c) e.appendChild(c);
    }
    return e;
  }

  function toast(kind, title, msg){
    let host=document.querySelector(".vsp-toast");
    if(!host){
      host=el("div",{class:"vsp-toast"});
      document.body.appendChild(host);
    }
    const t=el("div",{class:"t"});
    t.innerHTML = `<b>${title}</b><div style="opacity:.78;margin-top:4px">${msg||""}</div>`;
    if(kind==="good") t.style.borderColor="rgba(47,227,154,.45)";
    if(kind==="warn") t.style.borderColor="rgba(255,204,102,.45)";
    if(kind==="bad")  t.style.borderColor="rgba(255,92,122,.45)";
    host.prepend(t);
    setTimeout(()=>{ try{t.remove();}catch(e){} }, 6500);
  }

  async function getJSON(url){
    const r=await fetch(url, {method:"GET"});
    const ct=(r.headers.get("content-type")||"");
    let data=null;
    try{ data = ct.includes("application/json") ? await r.json() : await r.text(); }
    catch(e){ data = await r.text().catch(()=> ""); }
    return {ok:r.ok, status:r.status, data};
  }

  function addTopbar(){
    if(document.querySelector(".vsp-topbar")) return;
    document.body.classList.add("vsp-shell-pad");

    const left = el("div",{class:"vsp-brand"},[
      el("div",{class:"vsp-dot"}),
      el("div",{},[
        el("div",{class:"vsp-title"},["VSP • Commercial UI"]),
        el("div",{class:"vsp-sub"},[page])
      ])
    ]);

    const stat = el("div",{class:"vsp-pill", id:"vspShellLastRun"},[
      el("span",{class:"vsp-muted"},["Last run:"]),
      el("b",{id:"vspShellLastRunId"},["—"]),
      el("span",{id:"vspShellLastRunBadge", class:"vsp-badge info", style:"margin-left:6px;"},["LIVE"])
    ]);

    const btnRuns = el("button",{class:"vsp-btn vsp-btn-primary", type:"button"},["Runs"]);
    btnRuns.onclick=()=> location.href="/runs";
    const btnData = el("button",{class:"vsp-btn", type:"button"},["Data Source"]);
    btnData.onclick=()=> location.href="/data_source";
    const btnRules = el("button",{class:"vsp-btn", type:"button"},["Rule Overrides"]);
    btnRules.onclick=()=> location.href="/rule_overrides";
    const btnSet = el("button",{class:"vsp-btn", type:"button"},["Settings"]);
    btnSet.onclick=()=> location.href="/settings";

    const btnReload = el("button",{class:"vsp-btn", type:"button"},["Reload"]);
    btnReload.onclick=()=> location.reload();

    const right = el("div",{class:"vsp-actions"},[stat, btnRuns, btnData, btnRules, btnSet, btnReload]);

    const bar = el("div",{class:"vsp-topbar"},[left, right]);
    document.body.appendChild(bar);

    // quick last-run probe
    (async ()=>{
      const r=await getJSON("/api/vsp/runs?limit=1");
      if(r.ok && r.data && r.data.items && r.data.items[0]){
        const it=r.data.items[0];
        const rid = it.rid || it.run_id || it.id || "—";
        const overall=(it.overall || it.overall_status || "UNKNOWN").toString().toUpperCase();
        document.getElementById("vspShellLastRunId").textContent = rid;
        const b=document.getElementById("vspShellLastRunBadge");
        b.textContent = overall;
        b.className = "vsp-badge " + (overall==="GREEN"||overall==="OK"?"good":(overall==="RED"||overall==="FAIL"?"bad":(overall==="AMBER"||overall==="WARN"?"warn":"info")));
      }
    })().catch(()=>{});
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", addTopbar);
  else addTopbar();

  window.VSP_UI = { toast, getJSON };
})();
JS

# ---------- per-tab enhancers ----------
cat > static/js/vsp_runs_ops_v1.js <<'JS'
/* VSP_RUNS_OPS_V1 - live scan card + export buttons */
(()=> {
  if (window.__vsp_runs_ops_v1) return;
  window.__vsp_runs_ops_v1 = true;

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
      const r=await getJSON("/api/vsp/runs?limit=1");
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
JS

cat > static/js/vsp_datasource_explorer_v1.js <<'JS'
/* VSP_DATASOURCE_EXPLORER_V1 - client-side filter bar (safe) */
(()=> {
  if (window.__vsp_ds_explorer_v1) return;
  window.__vsp_ds_explorer_v1 = true;

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
JS

cat > static/js/vsp_rule_overrides_studio_v1.js <<'JS'
/* VSP_RULE_OVERRIDES_STUDIO_V1 - format/validate/save/apply (safe overlay) */
(()=> {
  if (window.__vsp_rules_studio_v1) return;
  window.__vsp_rules_studio_v1 = true;

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
JS

cat > static/js/vsp_settings_control_center_v1.js <<'JS'
/* VSP_SETTINGS_CONTROL_CENTER_V1 - health + config snapshot (safe overlay) */
(()=> {
  if (window.__vsp_settings_cc_v1) return;
  window.__vsp_settings_cc_v1 = true;

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
      const runs=await getJSON("/api/vsp/runs?limit=1");
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
JS

# ---------- inject into templates (auto-discover by title/url strings) ----------
python3 - <<'PY'
from pathlib import Path
import time, re

ts=time.strftime("%Y%m%d_%H%M%S")
tpl_dir=Path("templates")
if not tpl_dir.is_dir():
    print("[WARN] templates/ not found; skip inject.")
    raise SystemExit(0)

MARK="VSP_P1_UI_4TABS_COMMERCIAL_UPGRADE_V1"
shell_css = '<link rel="stylesheet" href="/static/css/vsp_ui_shell_v1.css"/>\n'
shell_js  = '<script src="/static/js/vsp_ui_shell_v1.js?v={{ asset_v }}"></script>\n'

tab_js = {
  "runs":   '<script src="/static/js/vsp_runs_ops_v1.js?v={{ asset_v }}"></script>\n',
  "data":   '<script src="/static/js/vsp_datasource_explorer_v1.js?v={{ asset_v }}"></script>\n',
  "rules":  '<script src="/static/js/vsp_rule_overrides_studio_v1.js?v={{ asset_v }}"></script>\n',
  "settings":'<script src="/static/js/vsp_settings_control_center_v1.js?v={{ asset_v }}"></script>\n',
}

def backup(p:Path):
    b=p.with_name(p.name+f".bak_4tabs_{ts}")
    b.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    print("[BACKUP]", b)

def inject(p:Path, which:str):
    s=p.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        print("[OK] already:", p)
        return
    backup(p)
    add = f"\n<!-- {MARK} -->\n"
    if "</head>" in s:
        s = s.replace("</head>", add + shell_css + "</head>")
    else:
        s = add + shell_css + s
    if "</body>" in s:
        s = s.replace("</body>", shell_js + tab_js[which] + "</body>")
    else:
        s += "\n" + shell_js + tab_js[which]
    p.write_text(s, encoding="utf-8")
    print("[OK] injected", which, "=>", p)

# find best templates by title keywords
files=list(tpl_dir.glob("*.html"))
pick={"runs":None,"data":None,"rules":None,"settings":None}

def score(path:Path, text:str):
    name=path.name.lower()
    sc=0
    if "runs" in name: sc+=2
    if "data_source" in name or "datasource" in name: sc+=2
    if "rule" in name: sc+=2
    if "settings" in name: sc+=2
    if "vsp" in name: sc+=1
    if "Runs" in text or "Runs & Reports" in text: sc+=2
    if "Data Source" in text: sc+=2
    if "Rule Overrides" in text: sc+=2
    if "Settings" in text: sc+=2
    return sc

for p in files:
    t=p.read_text(encoding="utf-8", errors="replace")
    low=t.lower()
    if ("runs" in p.name.lower()) or ("runs" in low and "reports" in low) or ("vsp_runs" in p.name.lower()):
        if pick["runs"] is None: pick["runs"]=p
    if ("data_source" in p.name.lower()) or ("data source" in low):
        if pick["data"] is None: pick["data"]=p
    if ("rule" in p.name.lower()) or ("rule overrides" in low):
        if pick["rules"] is None: pick["rules"]=p
    if ("settings" in p.name.lower()) or ("vsp • settings" in low):
        if pick["settings"] is None: pick["settings"]=p

# fallback by best score
if pick["runs"] is None:
    pick["runs"]=max(files, key=lambda p: score(p,p.read_text(encoding="utf-8", errors="replace")))
if pick["data"] is None:
    pick["data"]=max(files, key=lambda p: score(p,p.read_text(encoding="utf-8", errors="replace")))
if pick["rules"] is None:
    pick["rules"]=max(files, key=lambda p: score(p,p.read_text(encoding="utf-8", errors="replace")))
if pick["settings"] is None:
    pick["settings"]=max(files, key=lambda p: score(p,p.read_text(encoding="utf-8", errors="replace")))

inject(pick["runs"], "runs")
inject(pick["data"], "data")
inject(pick["rules"], "rules")
inject(pick["settings"], "settings")
PY

echo "[OK] assets written: vsp_ui_shell_v1 + 4 tab enhancers"
echo "[DONE] restart UI:"
echo "  rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.*; bin/p1_ui_8910_single_owner_start_v2.sh"
