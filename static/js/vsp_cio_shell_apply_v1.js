(function(){
  try{
    document.documentElement.classList.add("vsp-cio");
    document.body.classList.add("vsp-cio");

    function wrap(el){
      if(!el) return;
      // avoid double wrap
      if(el.closest(".vsp-cio-wrap")) return;
      const w=document.createElement("div");
      w.className="vsp-cio-wrap";
      el.parentNode.insertBefore(w, el);
      w.appendChild(el);
    }

    // wrap known roots
    wrap(document.getElementById("vsp-dashboard-main"));
    wrap(document.getElementById("vsp-runs-main"));
    wrap(document.getElementById("vsp-data-source-main"));
    wrap(document.getElementById("vsp-settings-main"));
    wrap(document.getElementById("vsp-rule-overrides-main"));
    wrap(document.getElementById("vsp_tab_root"));

    // mark blocks/cards if needed (non-breaking)
    document.querySelectorAll(".card,.kpi-card,.panel,.box").forEach(el=>{
      if(!el.classList.contains("vsp-card")) el.classList.add("vsp-card");
    });
  }catch(e){}
})();
