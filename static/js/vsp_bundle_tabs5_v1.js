/* VSP_BUNDLE_TABS5_SAFE_V2 - prevents JS crash, loads core modules in-order */
(function(){
  'use strict';

/* P65_DOM_ALIAS_CONTAINERS_V1 */
(function(){
try{
var host=document.getElementById('vsp5_root')||document.getElementById('vsp-dashboard-main')||document.body;
var ids=["vsp-health-badge", "vsp-releases-fab", "vsp-ui-ok-badge", "vspLatestRid", "vspTabs", "vspTabs4ToastV2"];
for(var i=0;i<ids.length;i++){
  var id=ids[i];
  if(!id) continue;
  if(document.getElementById(id)) continue;
  var d=document.createElement('div'); d.id=id;
  d.style.cssText='display:contents';
  host.appendChild(d);
}
}catch(_){}}
)();


/* P64B_OVERLAY_LOADER_V1 */
(function(){
  try{
    if (window.__VSP_P64B_OVERLAY_LOADED) return;
    window.__VSP_P64B_OVERLAY_LOADED = true;
    var sc = document.createElement('script');
    sc.src = '/static/js/vsp_runtime_error_overlay_v1.js?v=' + Date.now();
    sc.defer = true;
    (document.head || document.documentElement).appendChild(sc);
  }catch(_){}
})();


  const scripts = [
    "/static/js/vsp_tabs3_common_v3.js",
    "/static/js/vsp_topbar_commercial_v1.js",
    "/static/js/vsp_ui_shell_v1.js",
    "/static/js/vsp_cio_shell_apply_v1.js",
    "/static/js/vsp_polish_apply_p2_safe_v2.js",
    "/static/js/vsp_fetch_guard_rid_v1.js",
    "/static/js/vsp_rid_persist_patch_v1.js",
    "/static/js/vsp_rid_switch_refresh_all_v1.js",
    "/static/js/vsp_tabs4_autorid_v1.js"
  ];

  function already(src){
    return !!document.querySelector('script[src="' + src + '"]');
  }
  function loadOne(src){
    return new Promise((resolve) => {
      if (already(src)) return resolve({src, ok:true, cached:true});
      const s = document.createElement("script");
      s.src = src;
      s.async = false;
      s.onload = () => resolve({src, ok:true});
      s.onerror = () => resolve({src, ok:false});
      (document.head || document.documentElement).appendChild(s);
    });
  }

  (async function(){
    const results = [];
    for (const src of scripts){
      try { results.push(await loadOne(src)); }
      catch(e){ results.push({src, ok:false, err:String(e||"")}); }
    }
    try { console.debug("[VSP] bundle tabs5 loaded", results); } catch(_){}
    window.__VSP_BUNDLE_TABS5_SAFE_V2 = { ok:true, results };
  })();
})();


/* VSP_P72B_LOAD_DASHBOARD_MAIN_V1 */
/* VSP_P81FIX_P72B_SCOPE_DASH_ONLY_V2 */
var __VSP_P81_DASH_OK=false;
try{var __p=(location&&location.pathname)||""; __VSP_P81_DASH_OK=(__p==="/vsp5"||__p==="/c/dashboard");}catch(e){}
(function(){
  try{
    var scripts = Array.prototype.slice.call(document.scripts || []);
    var has = scripts.some(function(sc){ return sc && sc.src && sc.src.indexOf("vsp_dashboard_main_v1.js")>=0; });
    if (has) return;

    var sc = document.createElement("script");
    sc.src = "/static/js/vsp_dashboard_main_v1.js?v=" + Date.now();
    sc.async = true;
    sc.onload = function(){ console.info("[VSP] dashboard_main_v1 loaded (P72B)"); };
    sc.onerror = function(e){ console.warn("[VSP] dashboard_main_v1 load FAILED (P72B)", e); };
if(__VSP_P81_DASH_OK){ document.head.appendChild(sc); }

  }catch(e){}
})();

/* VSP_P82_HIDE_DASHBOARD_NON_DASH_V1 */
(function(){
  try{
    var pn=(location.pathname||"");
    var isDash = (pn==="/vsp5" || pn==="/c/dashboard" || pn==="/dashboard");
    if(isDash) return;
    var css = [
      "#vsp-dashboard-main{display:none!important;}",
      "#vsp-dashboard-kpis{display:none!important;}",
      "#vsp-dashboard{display:none!important;}",
      ".vsp-dashboard{display:none!important;}",
      ".vsp-dashboard-kpi{display:none!important;}",
      ".vsp-kpi-strip{display:none!important;}"
    ].join("\\n");
    var st=document.createElement("style");
    st.setAttribute("data-vsp","p82-hide-dash-non-dash");
    st.textContent=css;
    (document.head||document.documentElement).appendChild(st);
    // best-effort remove if present
    ["vsp-dashboard-main","vsp-dashboard-kpis","vsp-dashboard"].forEach(function(id){
      var el=document.getElementById(id);
      if(el) el.style.display="none";
    });
  }catch(e){}
})();

