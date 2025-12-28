(function(){
  'use strict';

  // VSP_ROUTE_GUARD_RUNS_ONLY_V1
  function __vsp_is_runs_only_v1(){
    try {
      const h = (location.hash||"").toLowerCase();
      return h.startsWith("#runs") || h.includes("#runs/");
    } catch(_) { return false; }
  }
  if(!__vsp_is_runs_only_v1()){
    try{ console.info("[VSP_ROUTE_GUARD_RUNS_ONLY_V1] skip", "vsp_runs_overall_from_gate_shim_p0_v3.js", "hash=", location.hash); } catch(_){}
    return;
  }

  if (window.__VSP_RUNS_OVERALL_SHIM_P0_V3) return;
  window.__VSP_RUNS_OVERALL_SHIM_P0_V3 = true;

  const TAG='VSP_RUNS_OVERALL_SHIM_P0_V3';
  const RID_RE=/\bVSP_[A-Z0-9]+_\d{8}_\d{6}\b/;
  const cache=new Map(); // rid->overall

  function ensureStyle(){
    if (document.getElementById('vsp-ov-style-v3')) return;
    const st=document.createElement('style');
    st.id='vsp-ov-style-v3';
    st.textContent=`
      .vsp-ov-bdg{display:inline-flex;align-items:center;justify-content:center;
        padding:4px 10px;border-radius:999px;font-size:12px;font-weight:900;
        border:1px solid rgba(255,255,255,.14)}
      .vsp-ov-green{background:rgba(0,255,140,.12)}
      .vsp-ov-amber{background:rgba(255,190,0,.14)}
      .vsp-ov-red{background:rgba(255,70,70,.14)}
      .vsp-ov-na{background:rgba(160,160,160,.14)}
    `;
    document.head.appendChild(st);
  }

  function norm(v){
    v=String(v||'').toUpperCase();
    if (v==='OK') return 'GREEN';
    if (v==='FAIL') return 'RED';
    if (v==='DEGRADED') return 'AMBER';
    return v || '—';
  }
  function cls(v){
    v=norm(v);
    if (v==='GREEN') return 'vsp-ov-green';
    if (v==='AMBER') return 'vsp-ov-amber';
    if (v==='RED') return 'vsp-ov-red';
    return 'vsp-ov-na';
  }

  async function fetchOverall(rid){
    if (!rid) return '';
    if (cache.has(rid)) return cache.get(rid)||'';
    try{
      const r=await fetch(`/api/vsp/run_gate_summary_v1/${encodeURIComponent(rid)}`,{credentials:'same-origin'});
      const j=await r.json().catch(()=>null);
      const ov = j ? (j.overall?.status || j.overall || '') : '';
      const v = norm(ov);
      cache.set(rid, v);
      return v;
    } catch(_){
      cache.set(rid,'');
      return '';
    }
  }

  function findRunsTable(){
    const tables=[...document.querySelectorAll('table')];
    return tables.find(t => (t.innerText||'').includes('RUN ID') && (t.innerText||'').includes('OVERALL')) || null;
  }
  function headerIndex(table, name){
    const ths=[...table.querySelectorAll('thead th, thead td, th')];
    for (let i=0;i<ths.length;i++){
      const tx=(ths[i].innerText||'').trim().toUpperCase();
      if (tx===name) return i;
    }
    return -1;
  }
  function cellAt(row, idx){
    const tds=[...row.querySelectorAll('td')];
    return (idx>=0 && idx<tds.length) ? tds[idx] : null;
  }

  async function patchOnce(){
    ensureStyle();
    const table=findRunsTable();
    if (!table) return 0;

    const idxOverall = headerIndex(table,'OVERALL');
    if (idxOverall < 0) return 0;

    const rows=[...table.querySelectorAll('tbody tr')];
    let changed=0;

    for (const tr of rows){
      const m=(tr.innerText||'').match(RID_RE);
      const rid=m && m[0] ? m[0] : '';
      if (!rid) continue;

      const td=cellAt(tr, idxOverall);
      if (!td) continue;

      const cur=(td.innerText||'').trim().toUpperCase();
      if (cur && cur !== '—') continue;

      const ov=await fetchOverall(rid);
      if (!ov) continue;

      td.classList.add('vsp-ov-bdg');
      td.classList.remove('vsp-ov-green','vsp-ov-amber','vsp-ov-red','vsp-ov-na');
      td.classList.add(cls(ov));
      td.innerText=ov;
      td.title=`RID=${rid}`;
      changed++;
    }
    return changed;
  }

  function boot(){
    let ticks=0;
    const iv=setInterval(async ()=>{
      ticks++;
      const n=await patchOnce();
      if (n) console.log(`[${TAG}] patched`, n, 'cells');
      if (ticks>=120) clearInterval(iv); // ~2 phút
    }, 500);

    // mutation observer: runs render async
    const mo=new MutationObserver(()=>{ patchOnce(); });
    mo.observe(document.documentElement || document.body, {subtree:true, childList:true});
    setTimeout(()=>{ try{mo.disconnect();} catch(_){ } }, 120000);
  }

  if (document.readyState==='loading') document.addEventListener('DOMContentLoaded', boot, {once:true});
  else boot();
})();
