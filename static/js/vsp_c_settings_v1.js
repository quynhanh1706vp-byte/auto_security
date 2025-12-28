/* VSP_SETTINGS_P405 - keep P404 panel, kill legacy cards reliably (limited reaper) */
(function(){
  "use strict";
  const log=(...a)=>console.log("[settings:p405]",...a);

  const ROOT_ID="vsp_settings_p405_root";

  function el(tag, attrs, html){
    const e=document.createElement(tag);
    if(attrs) for(const [k,v] of Object.entries(attrs)){
      if(k==="class") e.className=v;
      else if(k==="style") e.setAttribute("style",v);
      else e.setAttribute(k,v);
    }
    if(html!==undefined) e.innerHTML=html;
    return e;
  }

  function cssOnce(){
    if(document.getElementById("vsp_settings_css_p405")) return;
    const css=`
      html,body{ background:#0b1020; }
      #${ROOT_ID}{ padding:16px; color:#eaeaea; }
      #${ROOT_ID} .h1{ font-size:18px; margin:0 0 12px 0; }
      #${ROOT_ID} .grid{ display:grid; grid-template-columns: 1.1fr .9fr; gap:12px; }
      #${ROOT_ID} .card{ border:1px solid rgba(255,255,255,.10); background:rgba(0,0,0,.18); border-radius:14px; padding:12px; }
      #${ROOT_ID} .card h2{ font-size:13px; margin:0 0 10px 0; opacity:.9; }
      #${ROOT_ID} table{ width:100%; border-collapse:collapse; font-size:12px; }
      #${ROOT_ID} td,#${ROOT_ID} th{ border-bottom:1px solid rgba(255,255,255,.08); padding:6px; text-align:left; }
      .vsp_p405_hidden{ display:none !important; }
      @media (max-width: 1100px){ #${ROOT_ID} .grid{ grid-template-columns:1fr; } }
    `;
    document.head.appendChild(el("style",{id:"vsp_settings_css_p405"},css));
  }

  function neverHide(node){
    if(!node) return true;
    if(node === document.documentElement || node === document.body) return true;
    // never hide our own root or its parents
    const root=document.getElementById(ROOT_ID);
    if(root && (node===root || node.contains(root) || root.contains(node))) return true;
    return false;
  }

  function hideByTextOnce(){
    const needles=[
      "Gate summary (live)",
      "Settings (live links + tool legend)",
      "Settings (live links",
      "Tools (8):",
      "Exports:"
      ,"PIN default (stored local)"
      ,"Set AUTO"
      ,"Set PIN GLOBAL"
      ,"Set USE RID"
      ,"Commercial behaviors"
    
];
    const nodes=Array.from(document.querySelectorAll("section,article,div,pre"));
    for(const n of nodes){
      const t=(n.innerText||"").trim();
      if(!t) continue;
      if(!needles.some(x=>t.includes(x))) continue;

      // climb to a card-like container but stop before body/html
      let p=n;
      for(let i=0;i<12 && p && p!==document.body; i++){
        const cls=(p.className||"").toString();
        const h=(p.getBoundingClientRect? p.getBoundingClientRect().height:0) || 0;
        if(cls.includes("card")||cls.includes("panel")||cls.includes("container")||h>=160) break;
        p=p.parentElement;
      }
      const target=p||n;
      if(neverHide(target)) continue;
      target.classList.add("vsp_p405_hidden");
      target.setAttribute("data-vsp-legacy-hidden","1");
    }
  }

  async function ensureViewerLoaded(){
    if(window.VSP && window.VSP.jsonViewer) return true;
    return await new Promise((resolve)=>{
      const s=document.createElement("script");
      s.src="/static/js/vsp_json_viewer_v1.js?v="+Date.now();
      s.onload=()=>resolve(true);
      s.onerror=()=>resolve(false);
      document.head.appendChild(s);
    });
  }

  async function fetchWithTimeout(url, timeoutMs){
    const ms=timeoutMs||4500;
    const ctl=new AbortController();
    const t=setTimeout(()=>ctl.abort(), ms);
    const t0=performance.now();
    try{
      const r=await fetch(url,{signal:ctl.signal,cache:"no-store",credentials:"same-origin"});
      const text=await r.text();
      let data=null; try{ data=JSON.parse(text);}catch(_){}
      return {ok:r.ok,status:r.status,ms:(performance.now()-t0),text,data};
    }catch(e){
      const name=(e&&e.name)?e.name:"Error";
      return {ok:false,status:0,ms:(performance.now()-t0),text:`${name}: ${String(e)}`,data:null};
    }finally{ clearTimeout(t); }
  }

  function badgeFor(status, ok){
    const cls = ok ? "ok" : (status===0 ? "mid" : "bad");
    const label = ok ? "OK" : (status===0 ? "TIMEOUT/ABORT" : "ERR");
    const style = cls==="ok" ? "background:rgba(0,255,0,.08)" :
                  cls==="mid" ? "background:rgba(255,255,0,.08)" :
                                "background:rgba(255,0,0,.08)";
    return `<span style="${style};border:1px solid rgba(255,255,255,.15);padding:2px 8px;border-radius:999px;font-size:11px;">${label} ${status}</span>`;
  }

  function probeUrls(){
    return [
      "/api/vsp/runs_v3?limit=5&include_ci=1",
      "/api/vsp/dashboard_kpis_v4",
      "/api/vsp/top_findings_v2?limit=5",
      "/api/vsp/trend_v1",
      "/api/vsp/exports_v1",
      "/api/vsp/run_status_v1",
    ];
  }

  async function render(){
    cssOnce();

    // Ensure root exists once
    let root=document.getElementById(ROOT_ID);
    if(!root){
      root=el("div",{id:ROOT_ID});
      document.body.prepend(root);
    }
    root.innerHTML="";
    root.appendChild(el("div",{class:"h1"},"Settings • P405 (legacy reaped)"));

    const grid=el("div",{class:"grid"});
    const left=el("div",{class:"card"});
    const right=el("div",{class:"card"});
    left.appendChild(el("h2",null,"Endpoint probes"));
    right.appendChild(el("h2",null,"Raw JSON (stable collapsible)"));

    const table=el("table");
    table.innerHTML=`<thead><tr><th>Endpoint</th><th>Status</th><th>Time</th></tr></thead><tbody></tbody>`;
    const tbody=table.querySelector("tbody");
    left.appendChild(table);

    const jsonBox=el("div");
    right.appendChild(jsonBox);

    grid.appendChild(left); grid.appendChild(right);
    root.appendChild(grid);

    const urls=probeUrls();
    const results=[];
    for(const u of urls){
      const r=await fetchWithTimeout(u,4500);
      results.push({url:u,...r});
      const tr=document.createElement("tr");
      tr.innerHTML=`<td><code>${u}</code></td><td>${badgeFor(r.status,r.ok)}</td><td>${Math.round(r.ms)} ms</td>`;
      tbody.appendChild(tr);
    }

    const viewerOk=await ensureViewerLoaded();
    if(viewerOk && window.VSP && window.VSP.jsonViewer){
      window.VSP.jsonViewer.render(jsonBox,{
        tab:"settings",
        ts:new Date().toISOString(),
        probes: results.map(r=>({
          url:r.url, ok:r.ok, status:r.status, ms:Math.round(r.ms),
          data: (r.data!==null ? r.data : undefined),
          text: (r.data===null ? (r.text||"").slice(0,900) : undefined),
        }))
      },{title:"Settings.probes",maxDepth:7});
    } else {
      jsonBox.innerHTML=`<pre style="white-space:pre-wrap;word-break:break-word;opacity:.9">${results.map(x=>x.text||"").join("\n\n")}</pre>`;
    }

    log("rendered");
  }

  function startLimitedReaper(){
    let n=0;
    const max=40; // 10s // 20*250ms = 5s
    const timer=setInterval(()=>{
      try{ hideByTextOnce(); }catch(_){}
      n++;
      if(n>=max) clearInterval(timer);
    },250);
    // run immediately too
    hideByTextOnce();
  }

  async function main(){
    startLimitedReaper();
    await render();
    // reaper again after render (legacy may appear later)
    startLimitedReaper();
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", main);
  else main();
})();


/* VSP_P473_LOADER_SNIPPET_V1 */
(function(){
  try{
    if (window.__VSP_SIDEBAR_FRAME_V1__) return;
    if (document.getElementById("vsp_c_sidebar_v1_loader")) return;
    var s=document.createElement("script");
    s.id="vsp_c_sidebar_v1_loader";
    s.src="/static/js/vsp_c_sidebar_v1.js?v="+Date.now();
    document.head.appendChild(s);
  }catch(e){}
})();
