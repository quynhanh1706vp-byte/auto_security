/* VSP_P0_PERSIST_RID_LOCALSTORAGE_V1 */
(function(){
  'use strict';

  const KEY = 'vsp_rid_last';

  function detectRidSelect(){
    const ids = ['#rid', '#RID', '#vsp-rid', '#vsp-rid-select', '#ridSelect', '#runRid', '#run-rid'];
    for (const id of ids){
      const el = document.querySelector(id);
      if (el && el.tagName === 'SELECT') return el;
    }
    // fallback: a SELECT whose options look like VSP_...
    const sels = Array.from(document.querySelectorAll('select'));
    for (const s of sels){
      const opts = Array.from(s.options||[]);
      if (opts.some(o => (o.value||'').startsWith('VSP_') || (o.text||'').startsWith('VSP_'))) return s;
    }
    return null;
  }

  function getRidFromUrl(){
    const u = new URL(window.location.href);
    return u.searchParams.get('rid') || '';
  }

  function setRidInUrl(rid){
    const u = new URL(window.location.href);
    u.searchParams.set('rid', rid);
    // keep path /vsp5 stable
    const target = u.toString();
    if (target !== window.location.href){
      window.history.replaceState({}, '', target);
    }
  }

  function boot(){
    try{
      const urlRid = getRidFromUrl();
      const saved  = localStorage.getItem(KEY) || '';

      // If no rid in URL but we have saved rid, redirect once to ensure server-side data uses rid consistently
      if (!urlRid && saved && (location.pathname === '/vsp5' || location.pathname.startsWith('/vsp5'))){
        const u = new URL(window.location.href);
        u.searchParams.set('rid', saved);
        window.location.replace(u.toString());
        return;
      }

      // Sync select + persist on change
      const sel = detectRidSelect();
      if (sel){
        // On load, if URL rid exists, persist it
        const current = urlRid || sel.value || '';
        if (current) localStorage.setItem(KEY, current);

        if (!sel.__vspPersistBound){
          sel.__vspPersistBound = true;
          sel.addEventListener('change', ()=>{
            const rid = sel.value || '';
            if (rid){
              localStorage.setItem(KEY, rid);
              setRidInUrl(rid);
            }
          }, {passive:true});
        }
      } else {
        // even if no select, still persist URL rid
        if (urlRid) localStorage.setItem(KEY, urlRid);
      }
    }catch(_e){}
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
