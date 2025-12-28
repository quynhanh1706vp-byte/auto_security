(function(){
  "use strict";

  function q(sel, root){ return (root||document).querySelector(sel); }
  function el(tag, attrs, kids){
    const e=document.createElement(tag);
    if (attrs){
      for (const k of Object.keys(attrs)){
        if (k==="text") e.textContent = String(attrs[k]);
        else if (k==="html") e.innerHTML = String(attrs[k]);
        else e.setAttribute(k, String(attrs[k]));
      }
    }
    (kids||[]).forEach(ch => e.appendChild(ch));
    return e;
  }

  function getRid(){
    try{
      if (typeof window.__vspGetRid === "function") {
        const r = String(window.__vspGetRid()||"").trim();
        if (r) return r;
      }
    }catch(_e){}
    try{
      const r = String(new URLSearchParams(location.search).get("rid")||"").trim();
      return r;
    }catch(_e){}
    return "";
  }

  function getPinMode(){
    try{
      const pm = localStorage.getItem("VSP_PIN_MODE") || "";
      return String(pm||"").trim();
    }catch(_e){}
    return "";
  }

  async function tryHead(path){
    try{
      const r = await fetch(path, { method:"GET", cache:"no-store" });
      // we only need headers; still OK if json body exists
      const h = r.headers;
      const relts = h.get("X-VSP-RELEASE-TS") || "";
      const relsha = h.get("X-VSP-RELEASE-SHA") || "";
      const assetv = h.get("X-VSP-ASSET-V") || "";
      return { relts, relsha, assetv, ok: r.ok };
    }catch(_e){}
    return { relts:"", relsha:"", assetv:"", ok:false };
  }

  function ensureStyle(){
    if (q("#vspCioTopbarStyle")) return;
    const css = `
      .vspCioBar{position:sticky;top:0;z-index:9999;background:#0b0f18;border-bottom:1px solid rgba(255,255,255,.08)}
      .vspCioWrap{max-width:1400px;margin:0 auto;padding:10px 14px;display:flex;gap:10px;align-items:center;flex-wrap:wrap}
      .vspCioTitle{font-weight:700;letter-spacing:.2px}
      .vspCioMono{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace;font-size:12px;opacity:.92}
      .vspCioPill{padding:4px 8px;border:1px solid rgba(255,255,255,.14);border-radius:999px;background:rgba(255,255,255,.04)}
      .vspCioOk{border-color:rgba(40,220,140,.35);background:rgba(40,220,140,.07)}
      .vspCioWarn{border-color:rgba(255,190,60,.35);background:rgba(255,190,60,.07)}
      .vspCioBad{border-color:rgba(255,80,80,.4);background:rgba(255,80,80,.07)}
      .vspCioRight{margin-left:auto;display:flex;gap:10px;align-items:center;flex-wrap:wrap}
      .vspCioBtn{cursor:pointer;user-select:none}
    `;
    const st = el("style",{id:"vspCioTopbarStyle", html: css});
    document.head.appendChild(st);
  }

  function insertBar(){
    ensureStyle();
    if (q("#vspCioBar")) return q("#vspCioBar");
    const bar = el("div",{id:"vspCioBar", class:"vspCioBar"});
    bar.appendChild(el("div",{class:"vspCioWrap"},[
      el("div",{class:"vspCioTitle", text:"VSP 2025"}),
      el("div",{id:"vspCioRid", class:"vspCioPill vspCioMono", text:"RID: (detecting...)"}),
      el("div",{id:"vspCioData", class:"vspCioPill vspCioMono", text:"DATA: (unknown)"}),
      el("div",{id:"vspCioPin", class:"vspCioPill vspCioMono vspCioBtn", text:"PIN: Auto"}),
      el("div",{class:"vspCioRight"},[
        el("div",{id:"vspCioRel", class:"vspCioPill vspCioMono", text:"REL: (loading...)"}),
        el("div",{id:"vspCioAsset", class:"vspCioPill vspCioMono", text:"ASSET: (loading...)"}),
      ])
    ]));
    document.body.insertBefore(bar, document.body.firstChild);
    return bar;
  }

  function classifyDataSource(fromPath, totalFindings){
    const fp = String(fromPath||"");
    if (fp.includes("/out/") && fp.includes("/unified/findings_unified.json")) return "GLOBAL_BEST";
    if (fp.includes("/out_ci/")) return "OUT_CI";
    if (fp) return "RID";
    if ((totalFindings||0) > 0) return "RID";
    return "UNKNOWN";
  }

  async function refresh(){
    insertBar();
    const rid = getRid();
    q("#vspCioRid").textContent = "RID: " + (rid || "(none)");
    // pin behavior
    const pin = getPinMode() || "Auto";
    q("#vspCioPin").textContent = "PIN: " + pin;

    // try to infer data source by calling findings_page_v3 (small)
    let fromPath="", totalFindings=0;
    try{
      const url = "/api/vsp/findings_page_v3?rid=" + encodeURIComponent(rid||"") + "&limit=1&offset=0";
      const r = await fetch(url, { cache:"no-store" });
      const j = await r.json().catch(()=>({}));
      fromPath = j.from_path || j.fromPath || "";
      totalFindings = Number(j.total_findings || j.totalFindings || j.total || 0) || 0;
    }catch(_e){}

    const ds = classifyDataSource(fromPath, totalFindings);
    const dataEl = q("#vspCioData");
    dataEl.textContent = "DATA: " + ds + (totalFindings ? (" ("+totalFindings+")") : "");
    dataEl.classList.remove("vspCioOk","vspCioWarn","vspCioBad");
    dataEl.classList.add(ds==="GLOBAL_BEST" ? "vspCioOk" : (ds==="UNKNOWN" ? "vspCioBad" : "vspCioWarn"));

    // release headers
    const head = await tryHead("/api/vsp/findings_page_v3?rid=" + encodeURIComponent(rid||"") + "&limit=1&offset=0");
    q("#vspCioRel").textContent = "REL: " + (head.relts || "(n/a)") + (head.relsha ? (" • "+head.relsha.slice(0,8)) : "");
    q("#vspCioAsset").textContent = "ASSET: " + (head.assetv || "(n/a)");

    // click pin pill toggles Auto -> PIN_GLOBAL -> USE_RID
    const pinEl = q("#vspCioPin");
    if (!pinEl.__bound){
      pinEl.__bound = true;
      pinEl.addEventListener("click", ()=>{
        const cur = (getPinMode() || "Auto").toUpperCase();
        const next = (cur==="AUTO") ? "PIN_GLOBAL" : (cur==="PIN_GLOBAL" ? "USE_RID" : "AUTO");
        try{ localStorage.setItem("VSP_PIN_MODE", next); }catch(_e){}
        pinEl.textContent = "PIN: " + next;
        // soft refresh
        try{ location.reload(); }catch(_e){}
      });
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", ()=>{ refresh(); });
  } else {
    refresh();
  }
})();
