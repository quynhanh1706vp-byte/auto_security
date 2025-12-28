/* VSP_PANE_TOGGLE_SAFE_V1: hide non-active panes based on hash route */
(function(){
  'use strict';

  function routeFromHash(h){
    h = (h||'').trim();
    if (!h) return 'dashboard';
    if (h[0] === '#') h = h.slice(1);
    // strip query-ish fragments: #runs&x=y or #runs?x=y
    h = h.split('&')[0].split('?')[0].trim();
    return h || 'dashboard';
  }

  function firstExistingId(ids){
    for (const id of ids){
      const el = document.getElementById(id);
      if (el) return el;
    }
    return null;
  }

  function setPaneVisible(pane, on){
    if (!pane) return;
    pane.style.display = on ? '' : 'none';
    pane.setAttribute('data-vsp-pane-visible', on ? '1' : '0');
  }

  function apply(){
    try{
      const r = routeFromHash(location.hash);
      const map = {
        dashboard: ['pane-dashboard','dashboard-pane','vsp-pane-dashboard'],
        runs:      ['pane-runs','runs-pane','vsp-pane-runs'],
        datasource:['pane-datasource','datasource-pane','vsp-pane-datasource'],
        settings:  ['pane-settings','settings-pane','vsp-pane-settings'],
        rules:     ['pane-rules','rules-pane','vsp-pane-rules'],
      };

      // show/hide panes if they exist
      const panes = {};
      Object.keys(map).forEach(k => panes[k] = firstExistingId(map[k]));
      Object.keys(panes).forEach(k => setPaneVisible(panes[k], k === r));

      // also mark active tab if present
      document.querySelectorAll('.vsp-tab,[data-tab]').forEach(a=>{
        const t = (a.getAttribute('data-tab') || (a.getAttribute('href')||'').replace('#','')).split('&')[0].split('?')[0];
        if (!t) return;
        if (t === r) a.classList.add('is-active');
        else a.classList.remove('is-active');
      });
    } catch(e){
      try{ console.warn("[VSP_PANE_TOGGLE_SAFE_V1] apply failed", e); } catch(_){}
    }
  }

  window.addEventListener('hashchange', apply, {passive:true});
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', apply);
  else apply();
})();
