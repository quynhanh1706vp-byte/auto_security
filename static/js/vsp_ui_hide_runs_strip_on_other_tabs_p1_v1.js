(function(){
  'use strict';
  if (window.__VSP_HIDE_RUNS_STRIP_P1_V1) return;
  window.__VSP_HIDE_RUNS_STRIP_P1_V1 = true;

  const TAG='VSP_HIDE_RUNS_STRIP_P1_V1';

  function findRunsStrip(){
    // Heuristic: find the bar that contains "Limit" + "Has findings" + "Degraded" near the top
    const els=[...document.querySelectorAll('div,section,header')];
    for (const el of els){
      const tx=(el.innerText||'');
      if (tx.includes('Limit') && tx.includes('Has findings') && tx.includes('Degraded') && tx.includes('Search')){
        return el;
      }
    }
    return null;
  }

  function setVisible(isRuns){
    const strip=findRunsStrip();
    if (!strip) return;
    // hide the whole parent block (usually card/container)
    const box = strip.closest('.vsp-card, .dashboard-card, section, div') || strip;
    box.style.display = isRuns ? '' : 'none';
  }

  function onRoute(){
    const h=(location.hash||'').toLowerCase();
    const isRuns = (h==='#runs' || h.startsWith('#runs'));
    setVisible(isRuns);
    console.log(`[${TAG}] route=${h} isRuns=${isRuns}`);
  }

  window.addEventListener('hashchange', onRoute);
  if (document.readyState==='loading') document.addEventListener('DOMContentLoaded', onRoute, {once:true});
  else onRoute();
})();
