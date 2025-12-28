/* VSP_RUNS_EXPORT_ZIP_PATCH_P0_V4 */
(function(){
  'use strict';
  if (window.__VSP_RUNS_EXPORT_ZIP_PATCH_P0_V4) return;
  window.__VSP_RUNS_EXPORT_ZIP_PATCH_P0_V4 = 1;

  function ridFromHref(href){
    try{
      const u = new URL(href, location.origin);
      if (!u.pathname.includes('/api/vsp/run_file')) return null;
      return u.searchParams.get('run_id');
    }catch(e){ return null; }
  }

  function addBtnNear(anchor, rid){
    const row = anchor.closest('tr') || anchor.parentElement;
    if (!row) return;
    if (row.querySelector('a[data-vsp-export-zip="1"]')) return;

    const a = document.createElement('a');
    a.textContent = 'Export ZIP';
    a.href = '/api/vsp/export_zip?run_id=' + encodeURIComponent(rid);
    a.setAttribute('data-vsp-export-zip','1');
    a.style.marginLeft = '8px';
    a.style.textDecoration = 'none';
    a.style.display = 'inline-block';
    a.style.padding = '7px 10px';
    a.style.borderRadius = '10px';
    a.style.fontWeight = '800';
    a.style.border = '1px solid rgba(90,140,255,.35)';
    a.style.background = 'rgba(90,140,255,.16)';
    a.style.color = 'inherit';
    anchor.insertAdjacentElement('afterend', a);
  }

  function patchOnce(){
    const links = Array.from(document.querySelectorAll('a[href*="/api/vsp/run_file"]'));
    if (!links.length) return;
    const seen = new Set();
    for (const a of links){
      const rid = ridFromHref(a.getAttribute('href')||'');
      if (!rid) continue;
      const key = rid + '::' + (a.closest('tr') ? a.closest('tr').rowIndex : 'x');
      if (seen.has(key)) continue;
      seen.add(key);
      addBtnNear(a, rid);
    }
  }

  // Initial + retry
  let n=0;
  const t=setInterval(()=>{ n++; patchOnce(); if(n>=60) clearInterval(t); }, 250);
  window.addEventListener('load', ()=>{ try{patchOnce();}catch(_e){} }, {once:true});

  // MutationObserver (best for JS-rendered table)
  const mo = new MutationObserver(()=>{ try{patchOnce();}catch(_e){} });
  mo.observe(document.documentElement, {childList:true, subtree:true});
})();
