(function(){
  if (window.__VSPC) return;
  const LS_KEY="vsp_pin_mode_v2"; // auto|global|rid
  const MODES=["auto","global","rid"];

  function rid(){
    const qs = new URLSearchParams(location.search);
    return (qs.get("rid") || document.body.getAttribute("data-rid") || "").trim();
  }
  function mode(){
    const m = (localStorage.getItem(LS_KEY) || "auto").toLowerCase();
    return MODES.includes(m) ? m : "auto";
  }
  function setMode(m){
    localStorage.setItem(LS_KEY, MODES.includes(m)?m:"auto");
  }
  function esc(s){ return String(s||"").replace(/[&<>"]/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;" }[c])); }
  function sevDot(sev){
    const s=(sev||"").toUpperCase();
    if (s==="CRITICAL") return "s-critical";
    if (s==="HIGH") return "s-high";
    if (s==="MEDIUM") return "s-medium";
    if (s==="LOW") return "s-low";
    return "s-info";
  }
  function shortFile(f){
    const s=String(f||"");
    const parts=s.split("/");
    return parts.slice(Math.max(0, parts.length-4)).join("/");
  }
  function searchable(it){
    const a = [it.severity,it.tool,it.scanner,it.title,it.file].filter(Boolean).join(" ");
    return a.toLowerCase();
  }
  async function jget(url){
    const r=await fetch(url, {cache:"no-store", credentials:"same-origin"});
    const txt=await r.text();
    try{ return JSON.parse(txt); }
    catch(e){ return {ok:false, _err:"json_parse", _head:txt.slice(0,220)}; }
  }

  function paintPills(info){
    const pr=document.getElementById("p-rid");
    const pd=document.getElementById("p-ds");
    const pp=document.getElementById("p-pin");
    if (pr) pr.textContent = "RID: " + (rid() || "(none)");
    if (pp) pp.textContent = "PIN: " + mode().toUpperCase();
    if (pd) pd.textContent = "DATA SOURCE: " + (info && info.data_source ? info.data_source : "…");
  }

  function nav(pin){
    setMode(pin);
    const u=new URL(location.href);
    u.searchParams.set("rid", rid());
    u.searchParams.set("pin", pin);
    location.href=u.toString();
  }

  let _refreshHandler = null;
  function onRefresh(fn){ _refreshHandler = fn; }

  function setActiveTab(){
    const active = document.body.getAttribute("data-active") || "";
    document.querySelectorAll(".tab[data-tab]").forEach(a=>{
      if (a.getAttribute("data-tab")===active) a.classList.add("active");
    });
  }

  document.addEventListener("DOMContentLoaded", ()=>{
    setActiveTab();
    const bA=document.getElementById("b-auto");
    const bG=document.getElementById("b-global");
    const bR=document.getElementById("b-rid");
    const bF=document.getElementById("b-refresh");
    if (bA) bA.addEventListener("click", ()=>nav("auto"), {passive:true});
    if (bG) bG.addEventListener("click", ()=>nav("global"), {passive:true});
    if (bR) bR.addEventListener("click", ()=>nav("rid"), {passive:true});
    if (bF) bF.addEventListener("click", ()=>{ if (_refreshHandler) _refreshHandler(); }, {passive:true});

    // Always refresh pills using findings_page_v3 (ground truth)
    (async ()=>{
      try{
        const f = await jget(`/api/vsp/findings_page_v3?rid=${encodeURIComponent(rid())}&limit=1&offset=0&pin=${encodeURIComponent(mode())}`);
        if (f && f.ok) paintPills(f);
        else paintPills({});
      }catch(e){ paintPills({}); }
    })();
  }, {once:true});

  window.__VSPC = { rid, mode, setMode, esc, sevDot, shortFile, searchable, jget, paintPills, onRefresh };
})();
