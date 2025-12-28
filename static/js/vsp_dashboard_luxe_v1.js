
/* P66_LUXE_API_COMPAT_V1: rewrite legacy API urls to v2 + attach rid when possible */
(function(){
  if (window.__vspFetchCompatPatched) return;
  window.__vspFetchCompatPatched = true;

  function getRid(){
    try{
      const u = new URL(location.href);
      return u.searchParams.get("rid") || u.searchParams.get("run_id") || "";
    }catch(e){ return ""; }
  }

  function normalizeToRel(url){
    try{
      if (typeof url !== "string") return "";
      if (url.startsWith("http://") || url.startsWith("https://")) {
        const u = new URL(url);
        if (u.origin !== location.origin) return url; // cross-origin: don't touch
        return u.pathname + u.search;
      }
      return url;
    }catch(e){ return url; }
  }

  function rewriteRel(url){
    try{
      url = normalizeToRel(url);

      // map old endpoints
      url = url.replace("/api/vsp/top_findings_v1", "/api/vsp/top_findings_v2");
      url = url.replace("/api/vsp/top_findings_v0", "/api/vsp/top_findings_v2");

      // datasource dashboard mode -> datasource?rid=<rid>
      if (url.includes("/api/vsp/datasource") && url.includes("mode=dashboard")) {
        const rid = getRid();
        url = "/api/vsp/datasource" + (rid ? ("?rid="+encodeURIComponent(rid)) : "");
      }

      // if calling datasource without rid, attach rid if we have one
      if (url.startsWith("/api/vsp/datasource") && !url.includes("rid=")) {
        const rid = getRid();
        if (rid) url += (url.includes("?") ? "&" : "?") + "rid=" + encodeURIComponent(rid);
      }

      return url;
    }catch(e){ return url; }
  }

  const _fetch = window.fetch;
  window.fetch = function(input, init){
    try{
      if (typeof input === "string") {
        return _fetch.call(this, rewriteRel(input), init);
      }
      if (input && typeof input === "object" && input.url) {
        const newUrl = rewriteRel(input.url);
        if (typeof newUrl === "string" && newUrl !== input.url) {
          input = new Request(newUrl, input);
        }
      }
    }catch(e){}
    return _fetch.call(this, input, init);
  };
})();

/* VSP_DASHBOARD_LUXE_SAFE_V2 - minimal, no-crash dashboard bootstrap */
(function(){
  'use strict';

  function el(tag, attrs){
    const x = document.createElement(tag);
    if(attrs){ for(const k of Object.keys(attrs)) x.setAttribute(k, attrs[k]); }
    return x;
  }
  function safeText(x, t){ try{ x.textContent = t; } catch(_){} }

  function renderOverlay(stats){
    const id="vsp_dash_luxe_safe_v2";
    let box = document.getElementById(id);
    if(!box){
      box = el("div", { id });
      box.style.position="fixed";
      box.style.right="14px";
      box.style.bottom="14px";
      box.style.zIndex="99999";
      box.style.padding="12px 14px";
      box.style.borderRadius="14px";
      box.style.background="rgba(10,16,28,0.92)";
      box.style.border="1px solid rgba(255,255,255,0.08)";
      box.style.boxShadow="0 10px 30px rgba(0,0,0,0.35)";
      box.style.fontFamily="ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto";
      box.style.fontSize="12px";
      box.style.color="rgba(255,255,255,0.86)";
      box.style.minWidth="260px";

      const title = el("div");
      title.style.fontWeight="700";
      title.style.marginBottom="8px";
      safeText(title, "VSP Dashboard (SAFE)");
      box.appendChild(title);

      const body = el("div", { id: id+"_body" });
      box.appendChild(body);

      document.body.appendChild(box);
    }
    const body = document.getElementById(id+"_body");
    if(!body) return;

    body.innerHTML = "";
    const lines = [
      ["RID", stats.rid || "(none)"],
      ["Total", String(stats.total || 0)],
      ["CRITICAL", String(stats.CRITICAL||0)],
      ["HIGH", String(stats.HIGH||0)],
      ["MEDIUM", String(stats.MEDIUM||0)],
      ["LOW", String(stats.LOW||0)],
      ["INFO", String(stats.INFO||0)],
      ["TRACE", String(stats.TRACE||0)]
    ];
    for(const [k,v] of lines){
      const row = el("div");
      row.style.display="flex";
      row.style.justifyContent="space-between";
      row.style.gap="10px";
      row.style.padding="2px 0";
      const a=el("span"); a.style.opacity="0.75"; safeText(a,k);
      const b=el("span"); b.style.fontWeight="700"; safeText(b,v);
      row.appendChild(a); row.appendChild(b);
      body.appendChild(row);
    }
  }

  function normSev(s){
    s = String(s||"").toUpperCase().trim();
    if(["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"].includes(s)) return s;
    if(s==="INFORMATIONAL") return "INFO";
    return "TRACE";
  }

  async function fetchTop(){
    const u = "/api/vsp/top_findings_v2?limit=200";
    const res = await fetch(u, { credentials:"same-origin" });
    if(!res.ok) throw new Error("HTTP "+res.status);
    return await res.json();
  }

  async function boot(){
    const stats = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0,total:0,rid:(window.__VSP_RID||null)};
    try{
      const j = await fetchTop();
      const items = Array.isArray(j.items) ? j.items : [];
      stats.total = (typeof j.total==="number") ? j.total : items.length;
      stats.rid = j.run_id || j.rid || stats.rid || null;
      for(const it of items){
        const sev = normSev(it.severity || it.sev || it.level);
        stats[sev] = (stats[sev]||0) + 1;
      }
    }catch(e){
      stats.err = String(e||"");
      try{ console.warn("[VSP] dashboard safe fetch failed", e); }catch(_){}
    }
    renderOverlay(stats);
    window.__VSP_DASHBOARD_LUXE_SAFE_V2 = { ok:true, stats };
  }

  if(document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", () => boot().catch(()=>{}));
  } else {
    boot().catch(()=>{});
  }
})();


/* VSP_P78_SAFE_PANEL_DEBUG_ONLY_V1
 * Hide SAFE panel by default (commercial). Show only when ?debug=1 or localStorage.vsp_safe_show=1.
 */
(function(){
  function hasDebug(){
    try{ return /(?:^|[?&])debug=1(?:&|$)/.test(String(location.search||"")); }catch(e){ return false; }
  }
  function wantShow(){
    try{ return (localStorage.getItem("vsp_safe_show")==="1"); }catch(e){ return false; }
  }
  function setShow(v){
    try{ localStorage.setItem("vsp_safe_show", v ? "1" : "0"); }catch(e){}
  }
  function findSafeRoot(){
    var nodes = document.querySelectorAll("div,span,b,strong");
    for (var i=0;i<nodes.length;i++){
      var t = (nodes[i].textContent||"").trim();
      if (t.indexOf("VSP Dashboard (SAFE)") >= 0){
        var el = nodes[i];
        for (var k=0;k<10 && el; k++){
          if (el.style && (el.style.position==="fixed" || el.style.position==="absolute")) return el;
          el = el.parentElement;
        }
        el = nodes[i].closest("div");
        if (el) return el;
      }
    }
    return null;
  }
  function apply(){
    var show = hasDebug() || wantShow();
    var root = findSafeRoot();
    if (!root) return;
    root.setAttribute("data-vsp-panel","safe");
    if (!show) root.style.display="none";
    else root.style.display="";
    // If this panel has a "Hide" button, make it persist
    try{
      var btns = root.querySelectorAll("button");
      for (var i=0;i<btns.length;i++){
        var b = btns[i];
        var txt = (b.textContent||"").trim().toLowerCase();
        if (txt==="hide" && !b.getAttribute("data-p78")){
          b.setAttribute("data-p78","1");
          b.addEventListener("click", function(){
            setShow(false);
            try{ root.style.display="none"; }catch(e){}
          }, true);
        }
      }
    }catch(e){}
  }
  function loop(n){
    apply();
    if (n<=0) return;
    setTimeout(function(){ loop(n-1); }, 200);
  }
  if (document.readyState==="loading"){
    document.addEventListener("DOMContentLoaded", function(){ loop(25); }, {once:true});
  } else {
    loop(25);
  }
})();

