/* VSP_PANE_TOGGLE_SAFE_V2: show only active pane by hash route */
(function(){
  'use strict';

  function routeFromHash(){
    var h = (location.hash || '').trim();
    if (!h) return 'dashboard';
    if (h[0] === '#') h = h.slice(1);
    h = h.split('?')[0].split('&')[0];
    h = (h || 'dashboard').toLowerCase();
    if (h === '' ) h = 'dashboard';
    return h;
  }

  function collectPanes(){
    var panes = [];
    // common ids we used across patches
    var fixed = [
      'vsp-dashboard-main','vsp-runs-main','vsp-datasource-main','vsp-settings-main','vsp-rules-main',
      'vsp-dashboard-pane','vsp-runs-pane','vsp-datasource-pane','vsp-settings-pane','vsp-rules-pane'
    ];
    fixed.forEach(function(id){
      var el = document.getElementById(id);
      if (el) panes.push(el);
    });

    // generic: any container that looks like a pane
    var q = document.querySelectorAll('[id^="vsp-"][id$="-main"],[id^="vsp-"][id$="-pane"],.vsp-pane,[data-vsp-pane]');
    for (var i=0;i<q.length;i++) panes.push(q[i]);

    // unique
    var seen = new Set();
    var out = [];
    panes.forEach(function(el){
      if (!el || !el.id && !el.getAttribute) return;
      var key = el.id ? ("#"+el.id) : ("@"+(el.getAttribute('data-vsp-pane')||''));
      if (!seen.has(key)) { seen.add(key); out.push(el); }
    });
    return out;
  }

  function matchPane(route, panes){
    // try by id conventions
    var candidates = [
      'vsp-'+route+'-main',
      'vsp-'+route+'-pane'
    ];
    for (var i=0;i<candidates.length;i++){
      var el = document.getElementById(candidates[i]);
      if (el) return el;
    }
    // try by data attr
    for (var j=0;j<panes.length;j++){
      var p = panes[j];
      try{
        var dv = (p.getAttribute && (p.getAttribute('data-vsp-pane')||'')).toLowerCase();
        if (dv && dv === route) return p;
      } catch(_){}
    }
    return null;
  }

  function apply(){
    try{
      var route = routeFromHash();
      var panes = collectPanes();
      var active = matchPane(route, panes) || matchPane('dashboard', panes);

      panes.forEach(function(p){
        try{
          // hide all
          p.style.display = 'none';
          p.style.visibility = 'hidden';
        } catch(_){}
      });

      if (active){
        try{
          active.style.display = '';
          active.style.visibility = 'visible';
        } catch(_){}
      }

      try{ console.info("[VSP_PANES] route=", route, "panes=", panes.length, "active=", active && (active.id || active.getAttribute('data-vsp-pane'))); } catch(_){}
    } catch(_){}
  }

  function onReady(fn){
    if (document.readyState === 'complete' || document.readyState === 'interactive') return fn();
    document.addEventListener('DOMContentLoaded', fn);
  }

  onReady(function(){
    apply();
    window.addEventListener('hashchange', function(){ apply(); }, {passive:true});
    // sometimes router updates DOM after hashchange; apply again shortly
    setTimeout(apply, 50);
    setTimeout(apply, 250);
  });
})();
