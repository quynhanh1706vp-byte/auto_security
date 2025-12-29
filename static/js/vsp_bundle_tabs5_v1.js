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



/* VSP_P963I_KPI_V2 */
;(function(){
  try{
    function ridFromURL(){
      try{
        var sp=new URLSearchParams(location.search||'');
        return String(sp.get('rid')||sp.get('RID')||'').trim();
      }catch(e){ return ''; }
    }
    function setText(sel,v){ var el=document.querySelector(sel); if(!el) return false; el.textContent=String(v); return true; }

    function updateKPIs(counts){
      var total=0;
      ['CRITICAL','HIGH','MEDIUM','LOW','INFO','TRACE'].forEach(function(k){ total += (counts[k]||0); });

      // common ids
      setText('#kpi_total', total);
      setText('#kpi_critical', counts.CRITICAL||0);
      setText('#kpi_high', counts.HIGH||0);
      setText('#kpi_medium', counts.MEDIUM||0);
      setText('#kpi_low', counts.LOW||0);
      setText('#kpi_info', counts.INFO||0);
      setText('#kpi_trace', counts.TRACE||0);

      // data attrs
      ['TOTAL','CRITICAL','HIGH','MEDIUM','LOW','INFO','TRACE'].forEach(function(k){
        var v=(k==='TOTAL')?total:(counts[k]||0);
        var el=document.querySelector('[data-kpi="'+k+'"],[data-kpi-key="'+k+'"],[data-sev="'+k+'"]');
        if(el) el.textContent=String(v);
      });

      // fallback: KPI cards by label text
      var map={TOTAL:total,CRITICAL:counts.CRITICAL||0,HIGH:counts.HIGH||0,MEDIUM:counts.MEDIUM||0,LOW:counts.LOW||0,INFO:counts.INFO||0,TRACE:counts.TRACE||0};
      Object.keys(map).forEach(function(k){
        var nodes=document.querySelectorAll('.kpi,label,span,div,strong,b,h3,h4');
        for(var i=0;i<nodes.length;i++){
          var t=(nodes[i].textContent||'').trim().toUpperCase();
          if(t===k){
            var box=nodes[i].closest('.kpi-card,.card,.box,.panel') || nodes[i].parentElement;
            if(!box) continue;
            var num=box.querySelector('.kpi-num,.num,.value,strong,b,span');
            if(num){ num.textContent=String(map[k]); break; }
          }
        }
      });
    }

    function ensureCioBlock(counts, meta){
      var root=document.getElementById('vsp_cio_kpi_root');
      if(!root){
        // create a visible block under the top area
        root=document.createElement('div');
        root.id='vsp_cio_kpi_root';
        root.style.cssText="margin:10px 0;padding:10px;border:1px solid rgba(255,255,255,.08);border-radius:10px";
        var host=document.querySelector('#main,.main,.content,body') || document.body;
        host.insertBefore(root, host.firstChild);
      }
      root.innerHTML='';
      var h=document.createElement('div');
      h.innerHTML='<b>CIO KPI (v2)</b> rid=<code>'+meta.rid+'</code> n='+meta.n;
      root.appendChild(h);

      var g=document.createElement('div');
      g.style.cssText="display:flex;gap:8px;flex-wrap:wrap;margin-top:8px";
      ['CRITICAL','HIGH','MEDIUM','LOW','INFO','TRACE'].forEach(function(k){
        var c=document.createElement('div');
        c.style.cssText="min-width:140px;flex:1;padding:10px;border-radius:10px;background:rgba(255,255,255,.03);cursor:pointer";
        c.innerHTML='<div style="opacity:.8;font-size:12px">'+k+'</div><div style="font-size:22px;font-weight:700">'+(counts[k]||0)+'</div>';
        c.onclick=function(){ location.href='/data_source?severity='+encodeURIComponent(k); };
        g.appendChild(c);
      });
      root.appendChild(g);
    }

    function run(){
      var rid=ridFromURL();
      if(!rid) return; // chỉ chạy khi bạn truyền rid (đúng như bạn đang làm)
      fetch('/api/vsp/kpi_counts_v2?rid='+encodeURIComponent(rid), {credentials:'same-origin'})
        .then(function(r){ return r.json(); })
        .then(function(j){
          console.log('[P963I] KPI v2', j);
          if(!j || !j.ok) return;
          updateKPIs(j.counts||{});
          ensureCioBlock(j.counts||{}, {rid: rid, n: j.n||0});
        })
        .catch(function(e){ console.warn('[P963I] KPI v2 fetch failed', e); });
    }

    if(document.readyState==='loading') document.addEventListener('DOMContentLoaded', run);
    else run();
  }catch(e){
    console.warn('[P963I] init error', e);
  }
})(); 
