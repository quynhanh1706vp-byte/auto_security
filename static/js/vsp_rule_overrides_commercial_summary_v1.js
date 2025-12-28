;(()=> {
  const MARK="VSP_P441_RULE_OVERRIDES_SUMMARY_V1";
  if (window.__VSP_P441_RULE_OVERRIDES__) return;
  window.__VSP_P441_RULE_OVERRIDES__ = 1;

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
    const t=[...document.querySelectorAll("textarea")];
    if(!t.length) return null;
    t.sort((a,b)=> (b.value||"").length - (a.value||"").length);
    return t[0];
  }
  function safeParse(s){ try{ return JSON.parse(s); } catch(e){ return null; } }

  function tableFromRules(rules){
    const wrap=el("div",{style:"overflow:auto;max-height:420px;border:1px solid rgba(255,255,255,.06);border-radius:12px"});
    const table=el("table",{style:"width:100%;border-collapse:collapse;font-size:13px"});
    const th=el("thead",{},el("tr",{},[
      el("th",{style:"text-align:left;padding:8px 10px;opacity:.8;position:sticky;top:0;background:rgba(10,16,28,.95)"}, "Rule"),
      el("th",{style:"text-align:left;padding:8px 10px;opacity:.8;position:sticky;top:0;background:rgba(10,16,28,.95)"}, "Tool"),
      el("th",{style:"text-align:left;padding:8px 10px;opacity:.8;position:sticky;top:0;background:rgba(10,16,28,.95)"}, "Action"),
      el("th",{style:"text-align:left;padding:8px 10px;opacity:.8;position:sticky;top:0;background:rgba(10,16,28,.95)"}, "Reason"),
    ]));
    const tb=el("tbody");
    for(const r of rules){
      tb.append(el("tr",{},[
        el("td",{style:"padding:8px 10px;opacity:.95;white-space:nowrap"}, r.id||r.rule||"(unknown)"),
        el("td",{style:"padding:8px 10px;opacity:.9"}, r.tool||r.source||"-"),
        el("td",{style:"padding:8px 10px;opacity:.9"}, r.action||r.override||r.severity||"-"),
        el("td",{style:"padding:8px 10px;opacity:.8;max-width:520px"}, (r.reason||r.note||"").slice(0,160)),
      ]));
    }
    table.append(th); table.append(tb);
    wrap.append(table);
    return wrap;
  }

  function install(){
    const ta=findJsonTextarea();
    if(!ta) return;
    if (ta.dataset && ta.dataset.vspP441==="1") return;
    if (ta.dataset) ta.dataset.vspP441="1";

    const raw=ta.value || ta.textContent || "";
    const j=safeParse(raw);

    let rules=[];
    if (j){
      if (Array.isArray(j.rules)) rules=j.rules;
      else if (j.rules && typeof j.rules==="object") rules=Object.values(j.rules);
      else if (j.overrides && Array.isArray(j.overrides)) rules=j.overrides;
    }

    const panel=el("div",{class:"vsp_card",style:"margin:10px 0;padding:12px;border-radius:12px;background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.06)"});
    const top=el("div",{style:"display:flex;align-items:center;justify-content:space-between;gap:10px"},[
      el("div",{style:"font-weight:700;letter-spacing:.2px"}, `Rule Overrides (Commercial) — ${rules.length} rules`),
      el("div",{style:"display:flex;gap:8px;align-items:center"},[])
    ]);

    const btn=el("button",{type:"button",style:"padding:6px 10px;border-radius:999px;border:1px solid rgba(255,255,255,.10);background:rgba(255,255,255,.04);color:#e8eefc;cursor:pointer"}, "Advanced JSON");
    btn.addEventListener("click", ()=>{
      const shown = (rawWrap.style.display !== "none");
      rawWrap.style.display = shown ? "none" : "block";
      btn.textContent = shown ? "Advanced JSON" : "Hide Advanced";
    });
    top.lastChild.append(btn);

    const body = rules.length ? tableFromRules(rules) : el("div",{style:"opacity:.8"}, "No rules parsed (still preserved in Advanced).");

    const rawWrap=el("div",{style:"display:none;margin-top:10px"});
    rawWrap.append(el("div",{style:"opacity:.7;margin:6px 0 8px 0;font-size:12px"}, "Advanced (raw JSON) — kept for rollback/audit."));
    rawWrap.append(ta);

    const anchor = ta.parentElement;
    (anchor && anchor.parentElement ? anchor.parentElement : document.body).insertBefore(panel, anchor || null);

    panel.append(top);
    panel.append(el("div",{style:"margin-top:10px"},body));
    panel.append(rawWrap);
  }

  if (document.readyState==="loading") document.addEventListener("DOMContentLoaded", install);
  else install();
})();
