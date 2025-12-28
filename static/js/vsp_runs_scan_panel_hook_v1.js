(function(){

  // VSP_ROUTE_GUARD_RUNS_ONLY_V1
  function __vsp_is_runs_only_v1(){
    try {
      const h = (location.hash||"").toLowerCase();
      return h.startsWith("#runs") || h.includes("#runs/");
    } catch(_) { return false; }
  }
  if(!__vsp_is_runs_only_v1()){
    try{ console.info("[VSP_ROUTE_GUARD_RUNS_ONLY_V1] skip", "vsp_runs_scan_panel_hook_v1.js", "hash=", location.hash); } catch(_){}
    return;
  }

  if (window.__VSP_RUNSCAN_HOOK_V1__) return;
  window.__VSP_RUNSCAN_HOOK_V1__ = true;

  function isRunsHash() {
    return (location.hash || "").toLowerCase().includes("runs");
  }

  function loadPanelOnce() {
    if (window.__VSP_RUNSCAN_PANEL_LOADED__) return;
    window.__VSP_RUNSCAN_PANEL_LOADED__ = true;

    // nếu panel đã được include bằng script tag thì không cần load lại
    var already = Array.from(document.scripts || []).some(function(s){
      return (s.src || "").includes("vsp_runs_scan_panel_ui_v1.js");
    });
    if (already) {
      console.log("[VSP_RUNSCAN_HOOK] panel js already in DOM");
      return;
    }

    var s = document.createElement("script");
    s.src = "/static/js/vsp_runs_scan_panel_ui_v1.js";
    s.defer = true;
    s.onload = function(){ console.log("[VSP_RUNSCAN_HOOK] panel js loaded"); };
    s.onerror = function(){ console.warn("[VSP_RUNSCAN_HOOK] failed to load panel js"); };
    document.head.appendChild(s);
  }

  function bindTabs() {
    // bắt click những element có text/id liên quan runs
    var nodes = Array.from(document.querySelectorAll("a,button,div"));
    nodes.forEach(function(x){
      var t = (x.textContent||"").trim().toLowerCase();
      var id = (x.id||"").toLowerCase();
      if (t === "runs & reports" || t === "runs" || id.includes("runs")) {
        if (x.__VSP_RUNSCAN_BOUND__) return;
        x.__VSP_RUNSCAN_BOUND__ = true;
        x.addEventListener("click", function(){
          setTimeout(function(){
            if (isRunsHash()) loadPanelOnce();
          }, 50);
        }, {passive:true});
      }
    });
  }

  window.addEventListener("hashchange", function(){
    if (isRunsHash()) loadPanelOnce();
  });

  window.addEventListener("load", function(){
    bindTabs();
    if (isRunsHash()) loadPanelOnce();
  });

  // retry vài lần vì router render chậm
  var n = 0;
  var it = setInterval(function(){
    n++;
    bindTabs();
    if (isRunsHash()) {
      loadPanelOnce();
      clearInterval(it);
    }
    if (n > 50) clearInterval(it);
  }, 200);
})();
