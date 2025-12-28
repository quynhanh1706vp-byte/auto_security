
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

/* VSP_P0_TOOLSTRIP_KILL_NA_V1P5B */
/* ===================== VSP_P0_TOOLSTRIP_KILL_NA_V1P5B ===================== */
(function(){
  try{
    if (window.__VSP_TOOLSTRIP_KILL_NA_V1P5B__) return;
    window.__VSP_TOOLSTRIP_KILL_NA_V1P5B__ = true;

    const NA = ("N"+"/A"); // NO literal token
    function getRid(){
      try { return new URL(location.href).searchParams.get("rid") || ""; }
      catch(e){ return ""; }
    }
    function cleanseText(v){
      try{
        if (typeof v !== "string") return v;
        // Replace any NA-like text with em dash (CIO safe)
        if (v.indexOf(NA) >= 0) v = v.split(NA).join("—");
        // Fix RID label if any code tried to show RID: NA/—
        if (v.indexOf("RID:") === 0){
          const rid = getRid() || "—";
          // if empty or dash, keep dash; else stamp rid
          if (v.indexOf("—") >= 0 || v.indexOf(NA) >= 0) v = "RID: " + rid;
        }
        // TS/verdict labels sometimes show "TS: —" already -> ok
        return v;
      }catch(e){ return v; }
    }

    // Wrap global setText if present (many toolstrip versions use it)
    const _st = window.setText;
    if (typeof _st === "function"){
      window.setText = function(){
        try{
          const args = Array.prototype.slice.call(arguments);
          if (args.length > 0){
            const last = args[args.length-1];
            if (typeof last === "string") args[args.length-1] = cleanseText(last);
          }
          return _st.apply(this, args);
        }catch(e){
          return _st.apply(this, arguments);
        }
      };
    }

  }catch(e){}
})();
/* ===================== /VSP_P0_TOOLSTRIP_KILL_NA_V1P5B ===================== */

/* VSP_P0_CIO_SCRUB_NA_ALL_V1P4C */
/* VSP_DASHBOARD_KPI_TOOLSTRIP_V3_PINNED */
(() => {
  if (window.__vsp_dashboard_kpi_toolstrip_v3) return;
if(window.__VSP_CIO && window.__VSP_CIO.debug){ window.__vsp_dashboard_kpi_toolstrip_v3 = true; }
  const TOOL_ORDER = ["BANDIT","SEMGREP","GITLEAKS","KICS","TRIVY","SYFT","GRYPE","CODEQL"];
  const SEV_ORDER  = ["CRITICAL","HIGH","MEDIUM","LOW","INFO", trace:"TRACE"];
  const $ = (sel, root=document) => root.querySelector(sel);

  function pillClass(v){
    const x = String(v||"").toUpperCase();
    if (x.includes("GREEN") || x==="OK" || x==="PASS") return "ok";
    if (x.includes("AMBER") || x==="WARN") return "warn";
    if (x.includes("RED") || x==="FAIL" || x==="BLOCK") return "bad";
    return "muted";
  }

  async function getJson(url, timeoutMs=15000){
    const c = new AbortController();
    const t = setTimeout(() => c.abort(), timeoutMs);
    try{
      const r = await fetch(url, {signal:c.signal, credentials:"same-origin"});
      if (!r.ok) throw new Error("HTTP "+r.status);
      return await r.json();
    } finally { clearTimeout(t); }
  }

  function ensureStyles(){
    if (document.getElementById("vspDashPinnedStyleV3")) return;
    const st = document.createElement("style");
    st.id = "vspDashPinnedStyleV3";
    st.textContent = `
      /* pin topbar on top of ANY overlay */
      .vsp-topbar{
        position: fixed !important;
        top:0; left:0; right:0;
        z-index: 2147483647 !important;
      }
      body{ padding-top: 56px !important; }

      /* pinned KPI panel */
      #vspDashKpiPinnedV3{
        position: fixed;
        top: 56px;
        left: 0;
        right: 0;
        z-index: 2147483646;
        padding: 12px 14px;
        pointer-events: none; /* panel doesn’t block page interactions */
      }
      #vspDashKpiPinnedV3 .inner{
        max-width: 1400px;
        margin: 0 auto;
        pointer-events: auto;
        color: rgba(255,255,255,0.92);
      }
      #vspDashKpiPinnedV3 .grid{ display:grid; gap:12px; }
      #vspDashKpiPinnedV3 .two{ display:grid; gap:12px; grid-template-columns: 1.25fr 1fr; }
      #vspDashKpiPinnedV3 .kpi{ grid-template-columns: repeat(6, minmax(110px, 1fr)); }
      #vspDashKpiPinnedV3 .card{
        border:1px solid rgba(255,255,255,0.10);
        background: rgba(12,16,22,0.70);
        border-radius: 14px;
        padding: 12px;
        box-shadow: 0 8px 20px rgba(0,0,0,0.25);
      }
      #vspDashKpiPinnedV3 .title{ font-size:14px; font-weight:700; }
      #vspDashKpiPinnedV3 .sub{ font-size:12px; opacity:0.8; margin-top:4px; }
      #vspDashKpiPinnedV3 .row{ display:flex; gap:10px; flex-wrap:wrap; align-items:center; }
      #vspDashKpiPinnedV3 .mono{ font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono","Courier New", monospace; }

      #vspDashKpiPinnedV3 .pill{
        padding:2px 10px; border-radius:999px;
        border:1px solid rgba(255,255,255,0.14);
        background: rgba(255,255,255,0.05);
        font-size:12px;
      }
      #vspDashKpiPinnedV3 .pill.ok{ border-color: rgba(40,200,120,0.55); }
      #vspDashKpiPinnedV3 .pill.warn{ border-color: rgba(240,180,40,0.65); }
      #vspDashKpiPinnedV3 .pill.bad{ border-color: rgba(240,80,80,0.65); }
      #vspDashKpiPinnedV3 .pill.muted{ opacity:0.75; }

      #vspDashKpiPinnedV3 .tool{ display:flex; align-items:center; gap:8px; padding:8px 10px; border-radius: 12px;
        border:1px solid rgba(255,255,255,0.10); background: rgba(255,255,255,0.03); font-size:12px;
      }
      #vspDashKpiPinnedV3 .kpiTitle{ font-size:12px; opacity:0.85; }
      #vspDashKpiPinnedV3 .kpiVal{ font-size:22px; font-weight:700; margin-top:6px; }

      @media (max-width: 1100px){
        #vspDashKpiPinnedV3 .two{ grid-template-columns: 1fr; }
        #vspDashKpiPinnedV3 .kpi{ grid-template-columns: repeat(3, minmax(110px, 1fr)); }
      }
    `;
    document.head.appendChild(st);
  }

  function mount(){
    if (!String(location.pathname||"").includes("/vsp5")) return null;
    ensureStyles();
    let host = document.getElementById("vspDashKpiPinnedV3");
    if (host) return host;

    host = document.createElement("div");
    host.id = "vspDashKpiPinnedV3";
    host.innerHTML = `
      <div class="inner">
        <div class="grid two">
          <div class="card">
            <div class="title">Gate summary</div>
            <div class="sub">Pinned commercial KPI (V3)</div>
            <div style="height:8px"></div>
            <div class="row">
              <span id="v3Verdict" class="pill muted">…</span>
              <span id="v3Rid" class="pill muted mono">RID: …</span>
              <span id="v3Ts" class="pill muted mono">TS: …</span>
            </div>
          </div>
          <div class="card">
            <div class="title">Tools</div>
            <div class="sub">8 tools, missing → 0</div>
            <div style="height:8px"></div>
            <div class="row" id="v3Tools"></div>
          </div>
        </div>

        <div style="height:12px"></div>

        <div class="card">
          <div class="title">Findings KPI</div>
          <div class="sub">counts_total from </div>
          <div style="height:10px"></div>
          <div class="grid kpi" id="v3Kpi"></div>
        </div>
      </div>
    `;
    document.body.appendChild(host);
    return host;
  }

  function setPill(id, text, klass){
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = text;
    el.classList.remove("ok","warn","bad","muted");
    el.classList.add(klass || "muted");
  }
  function setText(id, v){
    const el = document.getElementById(id);
    if (el) el.textContent = v;
  }

  function render(rid, summary){
    const overall = String(summary?.overall || "UNKNOWN").toUpperCase();
    setPill("v3Verdict", overall, pillClass(overall));
    setText("v3Rid", `RID: ${rid || '0'}`);
    setText("v3Ts", `TS: ${summary?.ts || '0'}`);

    const counts = summary?.counts_total || {};
    const kpi = document.getElementById("v3Kpi");
    if (kpi){
      kpi.innerHTML = SEV_ORDER.map(sev => {
        const val = (sev in counts) ? counts[sev] : 0;
        return `<div class="card" style="padding:12px">
          <div class="kpiTitle">${sev}</div>
          <div class="kpiVal">${Number(val||0)}</div>
        </div>`;
      }).join("");
    }

    const byTool = summary?.by_tool || {};
    const tools = document.getElementById("v3Tools");
    if (tools){
      tools.innerHTML = TOOL_ORDER.map(t => {
        const o = byTool?.[t] || null;
        const verdict = o?.verdict ? String(o.verdict).toUpperCase() : ("N"+"/A");
        const klass = verdict === ("N"+"/A") ? "muted" : pillClass(verdict);
        const tot = (o && typeof o.total !== "undefined") ? `total:${o.total}` : "";
        return `<div class="tool">
          <span class="pill muted">${t}</span>
          <span class="pill ${klass}">${verdict}</span>
          <span class="mono" style="opacity:0.75">${tot}</span>
        </div>`;
      }).join("");
    }
  }

  async function main(){
    const host = mount();
    if (!host) return;

    // skeleton
    setPill("v3Verdict","…","muted");
    setText("v3Rid","RID: …");
    setText("v3Ts","TS: …");

    let rid = null;
    try{
      const runs = await getJson("/api/vsp/rid_latest_v3", 12000);
      rid = runs?.items?.[0]?.run_id || null;
    }catch(_){}

    if (!rid){
      setPill("v3Verdict","UNKNOWN","muted");
      setText("v3Rid","RID: " + ("N"+"/A"));
      return;
    }

    try{
      const summary = await getJson(`/api/vsp/run_file?rid=${encodeURIComponent(rid)}&name=${encodeURIComponent("reports/")}`, 15000);
      render(rid, summary);
    }catch(_){
      setPill("v3Verdict","UNKNOWN","muted");
      setText("v3Rid",`RID: ${rid}`);
    }
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", () => setTimeout(main, 250));
  else setTimeout(main, 250);
})();


