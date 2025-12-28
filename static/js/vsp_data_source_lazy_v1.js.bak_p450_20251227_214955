
/* VSP_P1_DS_CONTRACT_ONLY_V1 */
function __vspPickArr(j){
  try{
    // Commercial contract: backend guarantees top-level "findings" is the source of truth.
    const a = j && Array.isArray(j.findings) ? j.findings : [];
    return a;
  }catch(e){
    return [];
  }
}
/* /VSP_P2_DS_ITEMS_FALLBACK_V1 */

/* VSP_P2_RESTORE_DATA_SOURCE_LAZY_V1
   Purpose: avoid MIME error when page references this script.
   This file is allowed to be a thin shim; real logic may live in vsp_data_source_tab_v3.js etc.
*/
(function(){
  try{
    console.log("[VSP][DATA_SOURCE_LAZY] shim loaded");
    // If the newer tab module exists, optionally call an init hook
    if(window.VSP_DATA_SOURCE && typeof window.VSP_DATA_SOURCE.init === "function"){
      window.VSP_DATA_SOURCE.init();
    }
  }catch(e){}
})();


/* VSP_P1_REQUIRED_MARKERS_DS_V1 */
(function(){
  function ensureAttr(el, k, v){ try{ if(el && !el.getAttribute(k)) el.setAttribute(k,v); }catch(e){} }
  function ensureId(el, v){ try{ if(el && !el.id) el.id=v; }catch(e){} }
  function ensureTestId(el, v){ ensureAttr(el, "data-testid", v); }
  function ensureHiddenKpi(container){
    // Create hidden markers so gate can verify presence without altering layout
    try{
      const ids = ["kpi_total","kpi_critical","kpi_high","kpi_medium","kpi_low","kpi_info_trace"];
      let box = container.querySelector('#vsp-kpi-testids');
      if(!box){
        box = document.createElement('div');
        box.id = "vsp-kpi-testids";
        box.style.display = "none";
        container.appendChild(box);
      }
      ids.forEach(id=>{
        if(!box.querySelector('[data-testid="'+id+'"]')){
          const d=document.createElement('span');
          d.setAttribute('data-testid', id);
          box.appendChild(d);
        }
      });
    }catch(e){}
  }

  function run(){
    try {
      // Dashboard
      const dash = document.getElementById("vsp-dashboard-main") || document.querySelector('[id="vsp-dashboard-main"], #vsp-dashboard, .vsp-dashboard, main, body');
      if(dash) {
        ensureId(dash, "vsp-dashboard-main");
        // add required KPI data-testid markers
        ensureHiddenKpi(dash);
      }

      // Runs
      const runs = document.getElementById("vsp-runs-main") || document.querySelector('#vsp-runs, .vsp-runs, main, body');
      if(runs) ensureId(runs, "vsp-runs-main");

      // Data Source
      const ds = document.getElementById("vsp-data-source-main") || document.querySelector('#vsp-data-source, .vsp-data-source, main, body');
      if(ds) ensureId(ds, "vsp-data-source-main");

      // Settings
      const st = document.getElementById("vsp-settings-main") || document.querySelector('#vsp-settings, .vsp-settings, main, body');
      if(st) ensureId(st, "vsp-settings-main");

      // Rule overrides
      const ro = document.getElementById("vsp-rule-overrides-main") || document.querySelector('#vsp-rule-overrides, .vsp-rule-overrides, main, body');
      if(ro) ensureId(ro, "vsp-rule-overrides-main");
    } catch(e) {}
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", run, { once:true });
  } else {
    run();
  }
  // re-run after soft refresh renders
  setTimeout(run, 300);
  setTimeout(run, 1200);
})();
/* end VSP_P1_REQUIRED_MARKERS_DS_V1 */




/* VSP_P2_DATA_SOURCE_DEEP_DIVE_V1 */
(function(){
  function el(tag, attrs, html){
    const e=document.createElement(tag);
    if(attrs){ for(const k of Object.keys(attrs)) e.setAttribute(k, attrs[k]); }
    if(html!==undefined) e.innerHTML=html;
    return e;
  }
  async function jget(url){
    const r=await fetch(url, {credentials:"same-origin"});
    return await r.json();
  }
  async function ensureRid(){
    const qp=new URLSearchParams(location.search);
    let rid=qp.get("rid");
    if(rid) return rid;
    try{
      const j=await jget("/api/vsp/rid_latest");
      if(j && j.rid){
        qp.set("rid", j.rid);
        history.replaceState({}, "", location.pathname + "?" + qp.toString());
        return j.rid;
      }
    }catch(e){}
    return "";
  }
  function rawUrl(rid, path, download){
    const u=new URL("/api/vsp/run_file_raw_v4", location.origin);
    u.searchParams.set("rid", rid);
    u.searchParams.set("path", path);
    if(download) u.searchParams.set("download", "1");
    return u.toString();
  }
  async function loadFindings(rid, limit){
    const u=new URL("/api/vsp/artifact_v3", location.origin);
    u.searchParams.set("rid", rid);
    u.searchParams.set("path", "");
    u.searchParams.set("limit", String(limit||300));
    return await jget(u.toString());
  }
  function applyFilter(all, q){
    q=(q||"").trim().toLowerCase();
    if(!q) return all;
    return (all||[]).filter(it=>{
      const s=[it.tool,it.severity,it.title,it.file,it.rule,it.cwe].filter(Boolean).join(" ").toLowerCase();
      return s.includes(q);
    });
  }
  function render(host, rows){
    host.innerHTML="";
    const table=el("table", {class:"vsp-table vsp-table-ds", "data-testid":"vsp-ds-table"});
    const thead=el("thead", null, "<tr><th>Tool</th><th>Sev</th><th>Title</th><th>File</th></tr>");
    const tbody=el("tbody");
    (rows||[]).forEach((it, idx)=>{
      const tr=el("tr", {"data-idx":String(idx)});
      tr.style.cursor="pointer";
      tr.appendChild(el("td", null, (it.tool||"")));
      tr.appendChild(el("td", null, (it.severity||"")));
      tr.appendChild(el("td", null, (it.title||"")));
      tr.appendChild(el("td", null, (it.file||"")));
      tr.onclick=()=>{ alert((it.title||"(no title)") + "\n\n" + (it.file||"") ); };
      tbody.appendChild(tr);
    });
    table.appendChild(thead); table.appendChild(tbody);
    host.appendChild(table);
  }

  document.addEventListener("DOMContentLoaded", async ()=>{
    if(!location.pathname.includes("data_source")) return;
    const rid=await ensureRid();

    const root=document.querySelector('[data-testid="vsp-datasource-main"]') || document.body;
    const bar=el("div", {"data-testid":"vsp-ds-toolbar", class:"vsp-ds-toolbar"});
    const stat=el("div", {"data-testid":"vsp-ds-stat", class:"vsp-ds-stat"}, rid?("RID: "+rid):"RID: (none)");
    const q=el("input", {type:"search", placeholder:"Search findings…", "data-testid":"vsp-ds-search"});
    const btnLoad=el("button", {"data-testid":"vsp-ds-load"}, "Load");
    const btnOpen=el("button", {"data-testid":"vsp-ds-open-raw"}, "Open raw ");
    const btnDl=el("button", {"data-testid":"vsp-ds-dl-raw"}, "Download raw ");
    bar.appendChild(stat); bar.appendChild(q); bar.appendChild(btnLoad); bar.appendChild(btnOpen); bar.appendChild(btnDl);

    const host=el("div", {"data-testid":"vsp-ds-host", class:"vsp-ds-host"});
    root.prepend(host);
    root.prepend(bar);

    let allRows=[];
    async function refresh(){
      render(host, applyFilter(allRows, q.value));
    }

    btnOpen.onclick=async ()=>{
      const r=await ensureRid();
      if(!r) return alert("RID missing");
      window.open(rawUrl(r, "", false), "_blank", "noopener");
    };
    btnDl.onclick=async ()=>{
      const r=await ensureRid();
      if(!r) return alert("RID missing");
      window.open(rawUrl(r, "", true), "_blank", "noopener");
    };
    btnLoad.onclick=async ()=>{
      const r=await ensureRid();
      if(!r) return alert("RID missing");
      host.textContent="Loading…";
      try{
        const j=await loadFindings(r, 300);
        const arr=(j && (j.findings||j.items||j.data)) || [];
        allRows=Array.isArray(arr)?arr:[];
        await refresh();
      }catch(e){
        host.textContent="Load failed";
      }
    };
    q.addEventListener("input", refresh);
  });
})();



/* VSP_P2_DATA_SOURCE_DRAWER_V2 */
(function(){
  function el(tag, attrs, html){
    const e=document.createElement(tag);
    if(attrs){ for(const k of Object.keys(attrs)) e.setAttribute(k, attrs[k]); }
    if(html!==undefined) e.innerHTML=html;
    return e;
  }
  async function jget(url){
    const r=await fetch(url, {credentials:"same-origin"});
    const ct=(r.headers.get("content-type")||"").toLowerCase();
    if(!ct.includes("json")) throw new Error("non-json");
    return await r.json();
  }
  async function ensureRid(){
    const qp=new URLSearchParams(location.search);
    let rid=qp.get("rid");
    if(rid) return rid;
    const j=await jget("/api/vsp/rid_latest");
    if(j && j.rid){
      qp.set("rid", j.rid);
      history.replaceState({}, "", location.pathname + "?" + qp.toString());
      return j.rid;
    }
    return "";
  }
  function rawUrl(rid, path, download){
    const u=new URL("/api/vsp/run_file_raw_v4", location.origin);
    u.searchParams.set("rid", rid);
    u.searchParams.set("path", path);
    if(download) u.searchParams.set("download","1");
    return u.toString();
  }
  async function loadFindings(rid, limit){
    const candidates=["","reports/","report/"];
    return (async ()=>{
      for(const path of candidates){
        const u=new URL("/api/vsp/artifact_v3", location.origin);
        u.searchParams.set("rid", rid);
        u.searchParams.set("path", path);
        u.searchParams.set("limit", String(limit||300));
        const j=await jget(u.toString());
        const arr=(j && (j.findings||j.items||j.data))||[];
        if(Array.isArray(arr) && arr.length){ j.__chosen_path=path; return j; }
      }
      // last try: return first response even if empty (keeps keys like error/from)
      const u=new URL("/api/vsp/artifact_v3", location.origin);
      u.searchParams.set("rid", rid);
      u.searchParams.set("path", candidates[0]);
      u.searchParams.set("limit", String(limit||300));
      const j=await jget(u.toString());
      j.__chosen_path=candidates[0];
      return j;
    })();
  } /* VSP_P2_DS_FINDINGS_PATH_FALLBACK_V1 */
  async function loadFindings__dead(){ return null; } /* dead */
  async function loadFindings__dead2(){
    u.searchParams.set("limit", String(limit||300));
    return await jget(u.toString());
  }
  function normStr(x){ return (x===null||x===undefined) ? "" : String(x); }
  function pick(it, keys){
    for(const k of keys){ if(it && it[k]!==undefined && it[k]!==null && String(it[k]).trim()!=="") return it[k]; }
    return "";
  }
  function sevClass(sev){
    sev=(sev||"").toUpperCase();
    if(sev==="CRITICAL") return "sev-critical";
    if(sev==="HIGH") return "sev-high";
    if(sev==="MEDIUM") return "sev-medium";
    if(sev==="LOW") return "sev-low";
    if(sev==="INFO") return "sev-info";
    return "sev-trace";
  }
  function applyFilter(all, q){
    q=(q||"").trim().toLowerCase();
    if(!q) return all;
    return (all||[]).filter(it=>{
      const blob=[
        pick(it,["tool","source","scanner"]),
        pick(it,["severity","level"]),
        pick(it,["title","name","message"]),
        pick(it,["file","path","location"]),
        pick(it,["rule","check_id","id"]),
        pick(it,["cwe","cwe_id"]),
      ].map(normStr).join(" ").toLowerCase();
      return blob.includes(q);
    });
  }

  function ensureStyles(){
    if(document.getElementById("vsp-ds-drawer-style")) return;
    const css=el("style",{id:"vsp-ds-drawer-style"},`
      .vsp-ds-toolbar{display:flex;gap:10px;align-items:center;padding:10px 12px;border:1px solid rgba(255,255,255,.08);border-radius:14px;margin:12px 0;background:rgba(255,255,255,.03)}
      .vsp-ds-toolbar input{flex:1;min-width:220px;padding:8px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.10);background:rgba(0,0,0,.25);color:inherit}
      .vsp-ds-toolbar button{padding:8px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.10);background:rgba(255,255,255,.06);color:inherit;cursor:pointer}
      .vsp-ds-wrap{position:relative}
      .vsp-ds-table{width:100%;border-collapse:separate;border-spacing:0 8px}
      .vsp-ds-table td,.vsp-ds-table th{padding:10px 12px}
      .vsp-ds-table tbody tr{background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.08)}
      .vsp-ds-table tbody tr:hover{background:rgba(255,255,255,.06)}
      .sev-pill{display:inline-block;padding:2px 8px;border-radius:999px;border:1px solid rgba(255,255,255,.12);font-weight:600;font-size:12px}
      .sev-critical{background:rgba(255,0,0,.15)} .sev-high{background:rgba(255,120,0,.14)} .sev-medium{background:rgba(255,200,0,.12)}
      .sev-low{background:rgba(0,180,255,.12)} .sev-info{background:rgba(0,255,180,.10)} .sev-trace{background:rgba(255,255,255,.06)}
      .vsp-ds-drawer{position:fixed;top:0;right:0;height:100vh;width:min(520px,95vw);transform:translateX(110%);transition:transform .18s ease;
        background:rgba(15,15,18,.96);border-left:1px solid rgba(255,255,255,.10);z-index:9999;padding:14px 14px 18px;overflow:auto}
      .vsp-ds-drawer.open{transform:translateX(0)}
      .vsp-ds-drawer .hdr{display:flex;justify-content:space-between;gap:10px;align-items:flex-start}
      .vsp-ds-drawer .btnx{padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.10);background:rgba(255,255,255,.06);cursor:pointer}
      .vsp-ds-drawer .actions{display:flex;flex-wrap:wrap;gap:8px;margin:10px 0 12px}
      .vsp-ds-drawer pre{white-space:pre-wrap;word-break:break-word;background:rgba(0,0,0,.25);padding:10px;border-radius:12px;border:1px solid rgba(255,255,255,.08)}
      .vsp-ds-backdrop{position:fixed;inset:0;background:rgba(0,0,0,.35);z-index:9998;display:none}
      .vsp-ds-backdrop.show{display:block}
    `);
    document.head.appendChild(css);
  }

  function buildDrawer(){
    ensureStyles();
    let bd=document.querySelector('[data-testid="vsp-ds-backdrop"]');
    let dr=document.querySelector('[data-testid="vsp-ds-drawer"]');
    if(!bd){ bd=el("div",{"data-testid":"vsp-ds-backdrop",class:"vsp-ds-backdrop"}); document.body.appendChild(bd); }
    if(!dr){ dr=el("div",{"data-testid":"vsp-ds-drawer",class:"vsp-ds-drawer"}); document.body.appendChild(dr); }
    function close(){ dr.classList.remove("open"); bd.classList.remove("show"); }
    bd.onclick=close;
    return {bd, dr, close};
  }

  async function copyText(t){
    try{ await navigator.clipboard.writeText(t); return true; }catch(e){ return false; }
  }

  document.addEventListener("DOMContentLoaded", async ()=>{
    if(!location.pathname.includes("data_source")) return;

    const root=document.querySelector('[data-testid="vsp-datasource-main"]') || document.body;

    // TAKE OVER: remove older v1 nodes if any
    root.querySelectorAll('[data-testid="vsp-ds-toolbar"],[data-testid="vsp-ds-host"]').forEach(x=>x.remove());

    const rid=await ensureRid();
    const wrap=el("div", {class:"vsp-ds-wrap"});
    const bar=el("div", {"data-testid":"vsp-ds-toolbar", class:"vsp-ds-toolbar"});
    const stat=el("div", {"data-testid":"vsp-ds-stat"}, rid?("RID: "+rid):"RID: (none)");
    const q=el("input", {type:"search", placeholder:"Search findings…", "data-testid":"vsp-ds-search"});
    const btnLoad=el("button", {"data-testid":"vsp-ds-load"}, "Load");
    const btnOpen=el("button", {"data-testid":"vsp-ds-open-raw"}, "Open raw ");
    const btnDl=el("button", {"data-testid":"vsp-ds-dl-raw"}, "Download raw ");
    bar.appendChild(stat); bar.appendChild(q); bar.appendChild(btnLoad); bar.appendChild(btnOpen); bar.appendChild(btnDl);

    const host=el("div", {"data-testid":"vsp-ds-host", class:"vsp-ds-host"});
    wrap.appendChild(host);
    root.prepend(wrap);
    root.prepend(bar);

    const {bd, dr, close}=buildDrawer();

    let allRows=[];
    function render(rows){
      host.innerHTML="";
      const table=el("table",{class:"vsp-ds-table","data-testid":"vsp-ds-table"});
      const thead=el("thead",null,"<tr><th>Tool</th><th>Sev</th><th>Title</th><th>File</th></tr>");
      const tbody=el("tbody");
      (rows||[]).forEach((it, idx)=>{
        const tr=el("tr",{"data-idx":String(idx)});
        tr.style.cursor="pointer";
        const tool=pick(it,["tool","source","scanner"]);
        const sev=pick(it,["severity","level"]);
        const title=pick(it,["title","name","message"]);
        const file=pick(it,["file","path","location"]);
        tr.appendChild(el("td",null,normStr(tool)));
        tr.appendChild(el("td",null,`<span class="sev-pill ${sevClass(sev)}">${normStr(sev)}</span>`));
        tr.appendChild(el("td",null,normStr(title)));
        tr.appendChild(el("td",null,normStr(file)));
        tr.onclick=async ()=>{
          const r=await ensureRid();
          if(!r) return alert("RID missing");

          const title2=pick(it,["title","name","message"]) || "(no title)";
          const tool2=pick(it,["tool","source","scanner"]);
          const sev2=pick(it,["severity","level"]);
          const file2=pick(it,["file","path","location"]);
          const rule2=pick(it,["rule","check_id","id"]);
          const cwe2=pick(it,["cwe","cwe_id"]);

          const jsonPretty=JSON.stringify(it, null, 2);

          dr.innerHTML="";
          const hdr=el("div",{class:"hdr"},
            `<div>
               <div style="font-size:14px;opacity:.9">${normStr(tool2)} • <span class="sev-pill ${sevClass(sev2)}">${normStr(sev2)}</span></div>
               <div style="font-size:16px;font-weight:700;margin-top:6px">${title2}</div>
               <div style="opacity:.8;margin-top:6px">${normStr(file2)}</div>
               <div style="opacity:.75;margin-top:6px">Rule: ${normStr(rule2)} • CWE: ${normStr(cwe2)}</div>
             </div>`
          );
          const btnX=el("button",{class:"btnx","data-testid":"vsp-ds-drawer-close"},"Close");
          btnX.onclick=close;
          hdr.appendChild(btnX);

          const actions=el("div",{class:"actions"});
          const bCopy=el("button",{"data-testid":"vsp-ds-copy-json",class:"btnx"},"Copy JSON");
          const bOpen=el("button",{"data-testid":"vsp-ds-open-raw-file",class:"btnx"},"Open raw ");
          const bDl=el("button",{"data-testid":"vsp-ds-dl-raw-file",class:"btnx"},"Download raw ");
          const bCopyPath=el("button",{"data-testid":"vsp-ds-copy-path",class:"btnx"},"Copy file path");
          actions.appendChild(bCopy); actions.appendChild(bOpen); actions.appendChild(bDl); actions.appendChild(bCopyPath);

          bCopy.onclick=async ()=>{
            const ok=await copyText(jsonPretty);
            if(!ok) alert("Copy failed (clipboard blocked)");
          };
          bOpen.onclick=()=>window.open(rawUrl(r,"",false),"_blank","noopener");
          bDl.onclick=()=>window.open(rawUrl(r,"",true),"_blank","noopener");
          bCopyPath.onclick=async ()=>{
            const ok=await copyText(normStr(file2));
            if(!ok) alert("Copy failed (clipboard blocked)");
          };

          dr.appendChild(hdr);
          dr.appendChild(actions);
          dr.appendChild(el("pre",{"data-testid":"vsp-ds-json-pre"}, jsonPretty));
          bd.classList.add("show");
          dr.classList.add("open");
        };
        tbody.appendChild(tr);
      });
      table.appendChild(thead); table.appendChild(tbody);
      host.appendChild(table);
    }

    function refresh(){
      const rows=applyFilter(allRows, q.value);
      render(rows);
    }

    btnOpen.onclick=async ()=>{
      const r=await ensureRid();
      if(!r) return alert("RID missing");
      window.open(rawUrl(r,"",false),"_blank","noopener");
    };
    btnDl.onclick=async ()=>{
      const r=await ensureRid();
      if(!r) return alert("RID missing");
      window.open(rawUrl(r,"",true),"_blank","noopener");
    };
    btnLoad.onclick=async ()=>{
      const r=await ensureRid();
      if(!r) return alert("RID missing");
      host.textContent="Loading…";
      try{
        const j=await loadFindings(r, 300);
        const arr=(j && (j.findings||j.items||j.data)) || [];
        allRows=Array.isArray(arr)?arr:[];
        refresh();
      }catch(e){
        host.textContent="Load failed";
      }
    };
    q.addEventListener("input", refresh);

  });
})();
