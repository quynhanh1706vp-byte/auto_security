;(()=> {
  const MARK="VSP_P441_SETTINGS_SUMMARY_V1";
  if (window.__VSP_P441_SETTINGS_SUMMARY__) return;
  window.__VSP_P441_SETTINGS_SUMMARY__ = 1;

  function el(tag, attrs={}, kids=[]){
    const e=document.createElement(tag);
    for(const [k,v] of Object.entries(attrs||{})){
      if(k==="class") e.className=v;
      else if(k==="style") e.setAttribute("style", v);
      else if(k.startsWith("on") && typeof v==="function") e.addEventListener(k.slice(2), v);
      else e.setAttribute(k, String(v));
    }
    for(const k of (Array.isArray(kids)?kids:[kids])) if(k!=null) e.append(k.nodeType?k:document.createTextNode(String(k)));
    return e;
  }

  function findJsonTextarea(){
    // ưu tiên textarea lớn nhất
    const t=[...document.querySelectorAll("textarea")];
    if(!t.length) return null;
    t.sort((a,b)=> (b.value||"").length - (a.value||"").length);
    return t[0];
  }

  function safeParse(s){
    try{ return JSON.parse(s); } catch(e){ return null; }
  }

  function kvTable(rows){
    const table=el("table",{class:"vsp_tbl vsp_tbl_kv",style:"width:100%;border-collapse:collapse"});
    const tb=el("tbody");
    for(const [k,v] of rows){
      tb.append(el("tr",{},[
        el("td",{style:"padding:6px 10px;opacity:.9;white-space:nowrap;width:240px"},k),
        el("td",{style:"padding:6px 10px;opacity:.95"},v)
      ]));
    }
    table.append(tb);
    return table;
  }

  function summarizeSettings(j){
    const rows=[];
    const tools=(j && j.tools) ? j.tools : (j && j.config && j.config.tools) ? j.config.tools : null;
    if (tools && typeof tools === "object"){
      const names=Object.keys(tools);
      const enabled=names.filter(n => (tools[n] && tools[n].enabled===True) );
      // Python JSON uses true/false; in JS it’s true/false
      const enabled2=names.filter(n => (tools[n] && tools[n].enabled===true));
      rows.push(["Tools", `${enabled2.length}/${names.length} enabled`]);
      const timeouts=names.map(n=>{
        const t=tools[n] && (tools[n].timeout_sec ?? tools[n].timeout ?? null);
        return t!=null ? `${n}:${t}` : null;
      }).filter(Boolean).join(", ");
      if(timeouts) rows.push(["Timeouts", timeouts]);
    }
    // common keys fallbacks
    for (const k of ["mode","profile","degrade","degraded_ok","policy","severity_norm","runner","export","iso27001"]){
      if (j && j[k]!=null){
        const v=typeof j[k]==="object" ? JSON.stringify(j[k]).slice(0,160) : String(j[k]);
        rows.push([k, v]);
      }
    }
    if(!rows.length) rows.push(["Settings", "Loaded (no summary keys matched)"]);
    return rows;
  }

  function install(){
    const ta=findJsonTextarea();
    if(!ta) return;

    // Avoid double-install
    if (ta.dataset && ta.dataset.vspP441==="1") return;
    if (ta.dataset) ta.dataset.vspP441="1";

    const raw=ta.value || ta.textContent || "";
    const j=safeParse(raw);

    const panel=el("div",{class:"vsp_card",style:"margin:10px 0;padding:12px;border-radius:12px;background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.06)"});
    const title=el("div",{style:"display:flex;align-items:center;justify-content:space-between;gap:10px"},[
      el("div",{style:"font-weight:700;letter-spacing:.2px"}, "Settings (Commercial)"),
      el("div",{style:"display:flex;gap:8px;align-items:center"},[])
    ]);

    const btn=el("button",{type:"button",class:"btn",style:"padding:6px 10px;border-radius:999px;border:1px solid rgba(255,255,255,.10);background:rgba(255,255,255,.04);color:#e8eefc;cursor:pointer"}, "Advanced JSON");
    btn.addEventListener("click", ()=>{
      const shown = (rawWrap.style.display !== "none");
      rawWrap.style.display = shown ? "none" : "block";
      btn.textContent = shown ? "Advanced JSON" : "Hide Advanced";
    });
    title.lastChild.append(btn);

    const body=el("div",{style:"margin-top:10px"},[
      j ? kvTable(summarizeSettings(j)) : el("div",{style:"opacity:.8"}, "Cannot parse JSON in editor (still preserved in Advanced).")
    ]);

    // wrap raw textarea in collapsible
    const rawWrap=el("div",{style:"display:none;margin-top:10px"});
    const rawHint=el("div",{style:"opacity:.7;margin:6px 0 8px 0;font-size:12px"}, "Advanced (raw JSON) — kept for rollback/audit.");
    rawWrap.append(rawHint);
    rawWrap.append(ta);

    // insert panel before textarea original position
    const anchor = ta.parentElement;
    (anchor && anchor.parentElement ? anchor.parentElement : document.body).insertBefore(panel, anchor || null);

    panel.append(title);
    panel.append(body);
    panel.append(rawWrap);
  }

  if (document.readyState==="loading") document.addEventListener("DOMContentLoaded", install);
  else install();
})();
