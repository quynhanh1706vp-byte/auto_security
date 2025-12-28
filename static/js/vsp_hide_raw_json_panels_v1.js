/* VSP_HIDE_RAW_JSON_PANELS_V1 */
(function(){
  function isTargetPage(){
    const p = (location.pathname||"");
    return (
      p === "/c/settings" || p === "/c/rule_overrides" ||
      p === "/settings"   || p === "/rule_overrides"
    );
  }
  function hidePanels(){
    if(!isTargetPage()) return;

    // 1) Hide panels whose heading text looks like raw JSON viewers
    const needles = [/raw\s*json/i, /live\s*view/i, /stable\s*json/i, /collapse/i];
    const nodes = Array.from(document.querySelectorAll("h1,h2,h3,h4,div,span,label,b,strong,summary"));
    for (const n of nodes){
      const t = (n.textContent||"").trim();
      if(!t) continue;
      if(!needles.some(r=>r.test(t))) continue;

      // climb to a reasonable container
      let cur = n;
      for(let i=0;i<8 && cur;i++){
        if(cur.classList && (cur.classList.contains("card") || cur.classList.contains("panel"))) break;
        if(cur.tagName && ["SECTION","ARTICLE"].includes(cur.tagName)) break;
        cur = cur.parentElement;
      }
      if(cur && cur.style){
        cur.style.display = "none";
      }
    }

    // 2) As a fallback: if there are <pre> blocks that look like huge JSON dumps on these pages, hide them
    const pres = Array.from(document.querySelectorAll("pre"));
    for(const pre of pres){
      const tx = (pre.textContent||"");
      if(tx.length > 300 && (tx.includes('{"') || tx.includes('"}') || tx.includes('"tools"') || tx.includes('"rules"'))){
        pre.style.display = "none";
      }
    }
  }

  if(document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", hidePanels, {once:true});
  }else{
    hidePanels();
  }
})();
