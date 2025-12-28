/* VSP_PANE_TOGGLE_SAFE_V3: show only active route pane; hide Dashboard block on non-dashboard routes */
(function(){
  'use strict';

  function routeFromHash(){
    let h = (location.hash||'').trim();
    if (!h) return 'dashboard';
    if (h[0]==='#') h=h.slice(1);
    h = h.split('&')[0].split('?')[0].split('/')[0].trim();
    if (!h) return 'dashboard';
    return h.toLowerCase();
  }

  function q(sel){ try{return document.querySelector(sel);} catch(_){return null;} }
  function qa(sel){ try{return Array.from(document.querySelectorAll(sel));} catch(_){return [];} }

  function findDashboardBlock(){
    // heuristic: heading text == "Dashboard"
    const hs = qa('h1,h2,h3');
    for (const h of hs){
      const t = (h.textContent||'').trim().toLowerCase();
      if (t === 'dashboard'){
        const blk = h.closest('section,div,main');
        if (blk) return blk;
      }
    }
    return null;
  }

  function paneFor(route){
    // panes created by router logs: #vsp-runs-main, #vsp-datasource-main, #vsp-settings-main, #vsp-rules-main
    return (
      q('#vsp-' + route + '-main') ||
      q('#' + route + '-main') ||
      q('#pane-' + route) ||
      q('[data-pane="'+route+'"]')
    );
  }

  function apply(){
    const route = routeFromHash();

    // hide/show router panes if present
    const routes = ['dashboard','runs','datasource','settings','rules'];
    const panes = {};
    for (const r of routes){
      panes[r] = paneFor(r);
    }

    // If we can identify a container, hide sibling panes
    const activePane = panes[route] || panes['dashboard'] || null;
    if (activePane && activePane.parentElement){
      const parent = activePane.parentElement;
      const kids = Array.from(parent.children || []);
      for (const el of kids){
        const id = (el.id||'');
        const isKnownPane = /(^|)vsp-(dashboard|runs|datasource|settings|rules)-main$/.test(id) || /(^|)(dashboard|runs|datasource|settings|rules)-main$/.test(id);
        if (isKnownPane){
          el.style.display = (el === activePane) ? '' : 'none';
        }
      }
    }

    // Additionally, hide the Dashboard block on non-dashboard routes (fix “#runs still shows dashboard”)
    const dashBlk = findDashboardBlock();
    if (dashBlk){
      dashBlk.style.display = (route === 'dashboard') ? '' : 'none';
    }
  }

  window.addEventListener('hashchange', apply, {passive:true});
  window.addEventListener('load', function(){ setTimeout(apply, 0); }, {once:true});
})();
