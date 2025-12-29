// P920_OPS_PANEL_V1 (CIO: Ops + Evidence + Logs)
(function(){
  "use strict";
  const API_OPS="/api/vsp/ops_latest_v1";
  const API_JOUR="/api/vsp/journal_tail_v1?n=120";
  const API_LOG=(rid,tool)=>`/api/vsp/log_tail_v1?rid=${encodeURIComponent(rid||"")}&tool=${encodeURIComponent(tool||"")}&n=160`;
  const API_EVID=(rid)=>`/api/vsp/evidence_zip_v1?rid=${encodeURIComponent(rid||"")}`;

  function esc(s){ return String(s==null?"":s).replace(/[&<>\"']/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;" }[c])); }
  function el(tag, attrs={}, html=""){
    const n=document.createElement(tag);
    for(const k of Object.keys(attrs||{})){
      if(k==="class") n.className=attrs[k];
      else if(k==="style") n.setAttribute("style", attrs[k]);
      else n.setAttribute(k, attrs[k]);
    }
    if(html!=null) n.innerHTML=html;
    return n;
  }

  async function fetchJSON(url){
    const r = await fetch(url, {credentials:"same-origin"});
    let j=null, txt="";
    try{ txt = await r.text(); j = JSON.parse(txt||"{}"); }catch(e){ j=null; }
    return { ok:r.ok, status:r.status, json:j, text:txt, url };
  }

  function renderPanel(host, data){
    const rid = (data && (data.latest_rid || data.rid || (data.source||{}).rid)) || "";
    const ok = !!(data && data.ok);
    const degraded = (data && (data.degraded_tools||data.degraded||[])) || [];
    const degList = Array.isArray(degraded) ? degraded : [];
    const isDegraded = degList.length>0;

    host.innerHTML = "";
    const badge = ok && !isDegraded ? `<span class="chip ok">OK</span>` : `<span class="chip warn">DEGRADED</span>`;
    const rel = (data && (data.release_dir || (data.source||{}).release_dir)) || "";
    const base = (data && data.base) || "";
    const svc  = (data && data.svc)  || "";
    const ts   = (data && data.ts)   || "";

    host.appendChild(el("div",{class:"ops_hdr"},
      `<div class="ops_title">Ops Status (CIO)</div><div>${badge}</div>`
    ));

    const grid = el("div",{class:"ops_grid"});
    grid.appendChild(el("div",{class:"ops_kv"}, `<div class="k">service</div><div class="v">${esc(svc||"-")}</div>`));
    grid.appendChild(el("div",{class:"ops_kv"}, `<div class="k">base</div><div class="v">${esc(base||location.origin)}</div>`));
    grid.appendChild(el("div",{class:"ops_kv"}, `<div class="k">latest_rid</div><div class="v mono">${esc(rid||"-")}</div>`));
    grid.appendChild(el("div",{class:"ops_kv"}, `<div class="k">release_dir</div><div class="v mono">${esc(rel||"-")}</div>`));
    grid.appendChild(el("div",{class:"ops_kv"}, `<div class="k">ts</div><div class="v mono">${esc(ts||"-")}</div>`));
    host.appendChild(grid);

    const actions = el("div",{class:"ops_actions"});
    const btnRefresh = el("button",{class:"btn"}, "Refresh");
    btnRefresh.onclick = ()=>ensureMounted(true);
    actions.appendChild(btnRefresh);

    const btnJour = el("button",{class:"btn"}, "Journal tail");
    btnJour.onclick = ()=>showJournal();
    actions.appendChild(btnJour);

    const btnJSON = el("a",{class:"btn",href:API_OPS,target:"_blank"}, "View JSON");
    actions.appendChild(btnJSON);

    const btnE = el("a",{class:"btn",href:API_EVID(rid),target:"_blank"}, "Download evidence.zip");
    if(!rid) btnE.classList.add("disabled");
    actions.appendChild(btnE);

    host.appendChild(actions);

    // degraded tools
    const dWrap = el("div",{class:"ops_degraded"});
    dWrap.appendChild(el("div",{class:"ops_subttl"}, "Degraded tools"));
    if(degList.length===0){
      dWrap.appendChild(el("div",{class:"muted"}, "none"));
    }else{
      const ul = el("div",{class:"ops_toollist"});
      for(const t of degList){
        const tool = (t||"").toString();
        const a = el("a",{href:"#",class:"tool_link"}, esc(tool));
        a.onclick = (e)=>{ e.preventDefault(); showToolLog(rid, tool); };
        ul.appendChild(a);
      }
      dWrap.appendChild(ul);
    }
    host.appendChild(dWrap);
  }

  function ensureStyles(){
    if(document.getElementById("vsp_ops_panel_css_p920")) return;
    const css = `
      .vsp_ops_p920{ border:1px solid rgba(255,255,255,.06); border-radius:14px; padding:14px; margin-top:12px; background:rgba(255,255,255,.02); }
      .ops_hdr{ display:flex; align-items:center; justify-content:space-between; margin-bottom:10px; }
      .ops_title{ font-weight:700; letter-spacing:.2px; }
      .chip{ padding:2px 10px; border-radius:999px; font-size:12px; border:1px solid rgba(255,255,255,.14); }
      .chip.ok{ background:rgba(16,185,129,.12); }
      .chip.warn{ background:rgba(245,158,11,.12); }
      .ops_grid{ display:grid; grid-template-columns: 1fr 1fr; gap:10px; margin-bottom:10px; }
      .ops_kv{ padding:10px; border-radius:12px; background:rgba(0,0,0,.18); border:1px solid rgba(255,255,255,.06); }
      .ops_kv .k{ opacity:.65; font-size:12px; margin-bottom:4px; }
      .ops_kv .v{ font-size:13px; }
      .mono{ font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace; }
      .ops_actions{ display:flex; gap:8px; flex-wrap:wrap; margin:8px 0 6px; }
      .btn{ display:inline-block; padding:7px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.14); background:rgba(255,255,255,.04); color:inherit; text-decoration:none; cursor:pointer; font-size:13px; }
      .btn.disabled{ opacity:.4; pointer-events:none; }
      .ops_subttl{ font-weight:650; margin:10px 0 6px; }
      .muted{ opacity:.65; font-size:13px; }
      .ops_toollist{ display:flex; gap:8px; flex-wrap:wrap; }
      .tool_link{ padding:4px 10px; border-radius:999px; border:1px solid rgba(255,255,255,.12); text-decoration:none; }
      .modal_bg{ position:fixed; inset:0; background:rgba(0,0,0,.55); display:flex; align-items:center; justify-content:center; z-index:9999; }
      .modal{ width:min(980px, 92vw); max-height:86vh; overflow:auto; background:#0b1220; border:1px solid rgba(255,255,255,.12); border-radius:14px; box-shadow:0 14px 50px rgba(0,0,0,.45); }
      .modal_hd{ display:flex; justify-content:space-between; align-items:center; padding:12px 14px; border-bottom:1px solid rgba(255,255,255,.08); }
      .modal_bd{ padding:12px 14px; }
      pre{ white-space:pre-wrap; word-break:break-word; background:rgba(0,0,0,.22); border:1px solid rgba(255,255,255,.08); padding:12px; border-radius:12px; font-size:12px; }
    `;
    const st = document.createElement("style");
    st.id = "vsp_ops_panel_css_p920";
    st.textContent = css;
    document.head.appendChild(st);
  }

  function showModal(title, bodyText){
    const bg = el("div",{class:"modal_bg"});
    const m  = el("div",{class:"modal"});
    const hd = el("div",{class:"modal_hd"}, `<div class="mono">${esc(title||"")}</div>`);
    const close = el("button",{class:"btn"}, "Close");
    close.onclick = ()=>bg.remove();
    hd.appendChild(close);
    const bd = el("div",{class:"modal_bd"});
    bd.appendChild(el("pre",{}, esc(bodyText||"")));
    m.appendChild(hd); m.appendChild(bd); bg.appendChild(m);
    bg.onclick = (e)=>{ if(e.target===bg) bg.remove(); };
    document.body.appendChild(bg);
  }

  async function showJournal(){
    const r = await fetchJSON(API_JOUR);
    const j = r.json || {};
    const title = `journal_tail (${j.svc||""}) rc=${j.rc||""}`;
    const out = (j.out||"") + (j.err ? ("\n[stderr]\n"+j.err) : "");
    showModal(title, out || (r.text||""));
  }

  async function showToolLog(rid, tool){
    const url = API_LOG(rid, tool);
    const r = await fetchJSON(url);
    const j = r.json || {};
    const title = `log_tail tool=${tool} rid=${rid} ok=${j.ok}`;
    const out = j.tail || j.err || r.text || "";
    showModal(title, out);
  }

  async function ensureMounted(force){
    try{
      ensureStyles();
      const host = document.getElementById("vsp_ops_status_panel");
      if(!host) return;
      if(host.dataset.p920Mounted && !force) return;
      host.dataset.p920Mounted = "1";
      host.classList.add("vsp_ops_p920");
      host.innerHTML = `<div class="muted">Loading ops...</div>`;
      const r = await fetchJSON(API_OPS);
      renderPanel(host, r.json || {});
      console.log("[P920] ops panel mounted");
    }catch(e){
      console.warn("[P920] ops panel error", e);
    }
  }

  // public hook
  window.VSPOpsPanel = { ensureMounted };

  if(document.readyState==="loading"){
    document.addEventListener("DOMContentLoaded", ()=>ensureMounted(false));
  }else{
    ensureMounted(false);
  }
})();
