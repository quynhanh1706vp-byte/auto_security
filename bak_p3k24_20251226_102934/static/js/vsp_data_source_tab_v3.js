
/* ===================== VSP_P0_DS_API_ONLY_V1P0 =====================
   Data Source must NOT call run_file_allow/path internal files.
   Enforce paging contract via findings_page_v3.
============================================================================ */
(function(){
  try{
    if (window.__VSP_DS_BLOCK_RUNFILEALLOW_V1P0__) return;
    window.__VSP_DS_BLOCK_RUNFILEALLOW_V1P0__ = true;
    const _fetch = window.fetch ? window.fetch.bind(window) : null;
    if (!_fetch) return;
    window.fetch = function(input, init){
      try{
        const u = new URL(String(input), location.origin);
        if (u.origin === location.origin && u.pathname === "/api/vsp/run_file"){
          throw new Error("Commercial contract: Data Source must not use run_file_allow");
        }
      }catch(e){
        // if URL parse fails, let it pass
      }
      return _fetch(input, init);
    };
  }catch(e){}
})();
 /* ===================== /VSP_P0_DS_API_ONLY_V1P0 ===================== */

/* patched: force findings_safe_v1 */
/* VSP Data Source tab v3 (real data) */
(function(){
  if (window.__VSP_DS_V3_REALDATA) return;
  window.__VSP_DS_V3_REALDATA = true;

  const root = document.getElementById("vsp_tab_root");
  if (!root) return;

  const api = async (url, opt={}) => {
    const r = await fetch(url, Object.assign({credentials:"same-origin"}, opt));
    const j = await r.json().catch(()=>({ok:false,error:"bad_json"}));
    if (!j || j.ok !== true) throw new Error((j && (j.error||j.reason)) || ("API_FAIL "+url));
    return j;
  };

  const el = (t, a={}, c=[])=>{
    const n=document.createElement(t);
    for (const k in a){
      if (k==="style") Object.assign(n.style, a[k]);
      else if (k.startsWith("on")) n.addEventListener(k.slice(2), a[k]);
      else n.setAttribute(k, a[k]);
    }
    (Array.isArray(c)?c:[c]).forEach(x=>{
      if (x==null) return;
      if (typeof x==="string") n.appendChild(document.createTextNode(x));
      else n.appendChild(x);
    });
    return n;
  };

  let state = { rid:"", limit:50, offset:0, q:"", sev:"", tool:"" };

  root.innerHTML = "";
  const header = el("div", {style:{display:"flex",gap:"10px",alignItems:"center",flexWrap:"wrap",margin:"6px 0 12px 0"}}, []);
  const sel = el("select", {style:{padding:"6px 8px",minWidth:"360px"}}, []);
  const qin = el("input", {placeholder:"search in findings", style:{padding:"6px 8px",minWidth:"260px"}});

const sevSel = el("select", {style:{padding:"6px 8px", marginLeft:"8px", minWidth:"140px"}}, [
  el("option",{value:""},["All severities"]),
  el("option",{value:"CRITICAL"},["CRITICAL"]),
  el("option",{value:"HIGH"},["HIGH"]),
  el("option",{value:"MEDIUM"},["MEDIUM"]),
  el("option",{value:"LOW"},["LOW"]),
  el("option",{value:"INFO"},["INFO"]),
  el("option",{value:"TRACE"},["TRACE"]),
]);
sevSel.addEventListener("change", ()=>{ state.sev = (sevSel.value||""); state.offset=0; loadFindings(false); });

  const btn = el("button", {style:{padding:"6px 10px",cursor:"pointer"}, onclick:()=>loadFindings(true)}, ["Reload"]);
/* ===== VSP_P2_DS_QUERY_FILTER_V3_HOOK_ATTACH ===== */
try{ if(qin && qin.parentNode && !sevSel.parentNode) qin.parentNode.insertBefore(sevSel, btn||null); }catch(_){ }
  const stat = el("div", {style:{margin:"8px 0",opacity:"0.9"}}, ["Loading..."]);
  const table = el("div", {style:{marginTop:"8px"}}, []);

  header.appendChild(el("div",{style:{fontWeight:"700"}},["Data Source"]));
  header.appendChild(sel);
  header.appendChild(qin);
  header.appendChild(btn);

  root.appendChild(header);
  root.appendChild(stat);
  root.appendChild(table);

  qin.addEventListener("change", ()=>{ state.q = qin.value||""; state.offset=0; loadFindings(false); });


/* ===== VSP_P2_DS_ENSURE_RID_LATEST_SAFE_V1 ===== */
async function __vspDsEnsureRidLatestSafe(){
  try{
    if (state && state.rid) return true;

    // If URL has rid=..., use it
    try{
      const sp = new URL(window.location.href).searchParams;
      const ridq = String(sp.get("rid")||"").trim();
      if (ridq){
        state.rid = ridq;
        try{ const ridbox = document.querySelector('input[name="rid"], input#rid, input[data-testid="rid"], input[placeholder*="RID"]'); if(ridbox) ridbox.value = ridq; }catch(_){}
        return true;
      }
    }catch(_){}

    const url = "/api/vsp/rid_latest";
    for (let i=1;i<=4;i++){
      try{
        const ctl = new AbortController();
        const to = setTimeout(()=>{ try{ ctl.abort(); }catch(_){} }, 6000 + i*1500);
        const r = await fetch(url, {signal: ctl.signal, credentials:"same-origin", cache:"no-store"});
        clearTimeout(to);
        if (!r.ok) throw new Error("rid_latest http "+r.status);
        const j = await r.json();
        const rid = String((j && (j.rid||j.run_id||j.id)) || "").trim();
        if (rid){
          state.rid = rid;
          try{ const ridbox = document.querySelector('input[name="rid"], input#rid, input[data-testid="rid"], input[placeholder*="RID"]'); if(ridbox) ridbox.value = rid; }catch(_){}
          return true;
        }
      }catch(e){
        const msg = String(e && (e.name||e.message||e) || "");
        // AbortError/timeout => retry
        await new Promise(res=>setTimeout(res, 350*i));
      }
    }
  }catch(_){}
  return false;
}
try{ window.__vspDsEnsureRidLatestSafe = __vspDsEnsureRidLatestSafe; }catch(_){}

function __vspDsApplyQueryFromUrl(){
  try{
    const sp = new URL(window.location.href).searchParams;
    const sev = String(sp.get("severity")||"").toUpperCase().trim();
    const q = String(sp.get("q")||"").trim();
    const tool = String(sp.get("tool")||"").trim();
    if (typeof q === "string"){ state.q = q; if (qin) qin.value = q; }
    if (sev){ state.sev = sev; try{ if (typeof sevSel !== "undefined") sevSel.value = sev; }catch(_){ } }
    if (tool){ state.tool = tool; }
    state.offset = 0;
  }catch(_){}
}
try{ window.__vspDsApplyQueryFromUrl = __vspDsApplyQueryFromUrl; }catch(_){}


  function renderCounts(j){
    const c = j.counts || {};
    return `RID=${j.rid} • TOTAL=${c.TOTAL||0} • CRITICAL=${c.CRITICAL||0} HIGH=${c.HIGH||0} MEDIUM=${c.MEDIUM||0} LOW=${c.LOW||0} INFO=${c.INFO||0} TRACE=${c.TRACE||0}`;
  }

  function renderRows(items){

/* ===== VSP_P2_DS_QUERY_FILTER_V3_HOOK ===== */
try{
  if (items && items.length){
    const sevNeed = String(state.sev||"").toUpperCase().trim();
    const toolNeed = String(state.tool||"").toUpperCase().trim();
    if (sevNeed){
      items = items.filter(it => String(it.severity_norm||it.severity||it.level||"").toUpperCase() === sevNeed);
    }
    if (toolNeed){
      items = items.filter(it => String(it.tool||it.engine||"").toUpperCase().includes(toolNeed));
    }
  }
}catch(_){}

    table.innerHTML = "";
    if (!items || !items.length){
      table.appendChild(el("div",{style:{padding:"10px",border:"1px dashed #666",borderRadius:"8px"}},[
        "No findings to show."
      ]));
      return;
    }
    const t = el("table",{style:{width:"100%",borderCollapse:"collapse"}});
    const th = (x)=>el("th",{style:{textAlign:"left",borderBottom:"1px solid #555",padding:"8px"}},[x]);
    const td = (x)=>el("td",{style:{verticalAlign:"top",borderBottom:"1px solid #333",padding:"8px"}},[x]);

    t.appendChild(el("thead",{},[
      el("tr",{},[
        th("Severity"), th("Tool"), th("Title"), th("File"), th("Line"), th("Rule")
      ])
    ]));

    const tb = el("tbody");
    for (const it of items){
      const sev = String(it.severity_norm||it.severity||it.level||"INFO");
      const tool = String(it.tool||it.engine||it.source||"");
      const title = String(it.title||it.message||it.desc||it.check_name||it.rule_name||"(no title)");
      const file = String(it.file||it.path||it.filename||((it.location&&it.location.path)||""));
      const line = String(it.line||it.start_line||((it.location&&it.location.line)||"")||"");
      const rule = String(it.rule_id||it.rule||it.check_id||it.id||"");
      tb.appendChild(el("tr",{},[
        td(sev), td(tool), td(title), td(file), td(line), td(rule)
      ]));
    }
    t.appendChild(tb);
    table.appendChild(t);
  }

  async function loadRunsPick(){
    const j = await api("/api/ui/runs_v3?limit=200&offset=0");
    sel.innerHTML = "";
    let picked = "";
    for (const it of (j.items||[])){
      const label = `${it.rid} ${it.has_findings?"[F]":""}${it.has_gate?"[G]":""} ${it.overall||""}`.trim();
      sel.appendChild(el("option",{value:it.rid},[label]));
      if (!picked && it.has_findings) picked = it.rid;
    }
    if (!picked && (j.items||[]).length) picked = j.items[0].rid;
    state.rid = picked || "";
    sel.value = state.rid;
    sel.addEventListener("change", ()=>{ state.rid = sel.value; state.offset=0; loadFindings(false); });
  }

  async function loadFindings(){
    if (!state.rid) return;
    stat.textContent = "Loading findings...";
    table.innerHTML = "";
    try{
      const url = `/api/vsp/findings_page_v3?rid=${encodeURIComponent(state.rid)}&limit=${state.limit}&offset=${state.offset}&q=${encodeURIComponent(state.q||"")}`;
      const j = await api(url);
      stat.textContent = renderCounts(j);

      if (j.reason){
        table.appendChild(el("div",{style:{margin:"10px 0",padding:"10px",border:"1px dashed #666",borderRadius:"8px"}},[
          "Reason: "+j.reason,
          el("div",{style:{marginTop:"6px",opacity:"0.9"}},["Hint: "+(j.hint_paths||[]).join(" , ")])
        ]));
      }

      renderRows(j.items||[]);
      if (j.findings_path){
        table.appendChild(el("div",{style:{marginTop:"8px",opacity:"0.8",fontSize:"12px"}},["Source: "+j.findings_path]));
      }
    }catch(e){
      stat.textContent = "Error: "+(e && e.message ? e.message : String(e));
      table.innerHTML = "";
      table.appendChild(el("div",{style:{padding:"10px",border:"1px solid #a44",borderRadius:"8px"}},[
        "Failed to load findings. (Check console)"
      ]));
    }
  }

  (async ()=>{
    await loadRunsPick();
    try{ await __vspDsEnsureRidLatestSafe(); }catch(_){ }
    try{ __vspDsApplyQueryFromUrl(); }catch(_){ }
    await loadFindings();
  })();
})();


async function __vspDsFetchPageV1P0(rid, limit, offset, q, sev, tool){
  const sp = new URLSearchParams();
  sp.set("rid", String(rid||""));
  sp.set("limit", String(limit||200));
  sp.set("offset", String(offset||0));
  if (q) sp.set("q", String(q));
  if (sev) sp.set("sev", String(sev));
  if (tool) sp.set("tool", String(tool));
  const url = "/api/vsp/findings_page_v3?" + sp.toString();
  const r = await fetch(url, { credentials:"same-origin" });
  if (!r.ok) throw new Error("HTTP "+r.status+" for "+url);
  return await r.json();
}

/* ===== VSP_P2_DS_QUERY_FILTER_V1 ===== */
(function(){
  function qs(sel,root){ return (root||document).querySelector(sel); }
  function getParams(){
    try { return new URL(window.location.href).searchParams; } catch(e){ return null; }
  }
  function apply(){
    var sp=getParams(); if(!sp) return;
    var sev=(sp.get("severity")||"").toUpperCase();
    var q=(sp.get("q")||"").trim();

    // Best-effort: set UI controls if they exist
    var sevSel = qs("select[name='severity'], #severity, #sev, #vsp-f-sev, #vsp-p2-sev");
    if(sevSel && sev){ try{ sevSel.value=sev; }catch(_){ } }
    var qInp = qs("input[name='q'], #q, #search, #vsp-f-q, #vsp-p2-q");
    if(qInp && q){ try{ qInp.value=q; }catch(_){ } }

    // Try to trigger existing filtering mechanisms
    var btn = qs("button#apply, button[name='apply'], #apply, #btnApply, .apply, button[data-action='apply']");
    if(btn){ btn.click(); return; }

    // Fallback: dispatch input/change events so existing listeners run
    if(sevSel){ sevSel.dispatchEvent(new Event("change",{bubbles:true})); }
    if(qInp){ qInp.dispatchEvent(new Event("input",{bubbles:true})); qInp.dispatchEvent(new Event("change",{bubbles:true})); }
  }
  if(document.readyState!=="loading") setTimeout(apply, 50);
  else document.addEventListener("DOMContentLoaded", function(){ setTimeout(apply, 50); });
})();

/* ===== VSP_P2_FIX_APIUI_TO_APIVSP_V1 ===== */
