(function(){
  'use strict';
  if (window.__VSP_TOOL_PILLS_VERDICT_P0_V1) return;
  window.__VSP_TOOL_PILLS_VERDICT_P0_V1 = true;

  const TAG='VSP_TOOL_PILLS_VERDICT_P0_V1';
  const TOOLS=["BANDIT","SEMGREP","GITLEAKS","KICS","TRIVY","SYFT","GRYPE","CODEQL"];

  function ensureStyle(){
    if (document.getElementById('vsp-toolpill-style-v1')) return;
    const st=document.createElement('style');
    st.id='vsp-toolpill-style-v1';
    st.textContent=`
      .vsp-pill-v{display:inline-flex;align-items:center;gap:8px}
      .vsp-vbdg{display:inline-flex;align-items:center;justify-content:center;
        padding:3px 8px;border-radius:999px;font-size:11px;font-weight:900;
        border:1px solid rgba(255,255,255,.14)}
      .vsp-vg{background:rgba(0,255,140,.12)}
      .vsp-va{background:rgba(255,190,0,.14)}
      .vsp-vr{background:rgba(255,70,70,.14)}
      .vsp-vn{background:rgba(160,160,160,.14)}
    `;
    document.head.appendChild(st);
  }

  function map(v){
    v=String(v||'').toUpperCase();
    if (v==='OK') v='GREEN';
    if (v==='FAIL') v='RED';
    if (v==='DEGRADED') v='AMBER';
    if (v==='GREEN') return {t:'GREEN', c:'vsp-vbdg vsp-vg'};
    if (v==='AMBER') return {t:'AMBER', c:'vsp-vbdg vsp-va'};
    if (v==='RED') return {t:'RED', c:'vsp-vbdg vsp-vr'};
    return {t:'NOT_RUN', c:'vsp-vbdg vsp-vn'};
  }

  function getRID(){
    try{
      const v=localStorage.getItem('vsp_rid_selected_v2');
      if (v && String(v).trim()) return String(v).trim();
    } catch(_){}
    return '';
  }

  async function resolveRID(){
    const ls=getRID();
    if (ls) return ls;
    try{
      const r=await fetch('/api/vsp/runs_v3?limit=1&hide_empty=0&filter=1',{credentials:'same-origin'});
      const j=await r.json();
      return String(j?.items?.[0]?.run_id || '');
    } catch(_){ return ''; }
  }

  async function fetchGate(rid){
    const r=await fetch(`/api/vsp/run_gate_summary_v1/${encodeURIComponent(rid)}`,{credentials:'same-origin'});
    return await r.json();
  }

  function decorateByTool(by){
    // Find any element whose text starts with tool name (case-insensitive)
    const all=[...document.querySelectorAll('div,span,a,button')];
    let n=0;
    for (const tool of TOOLS){
      const el = all.find(x => {
        const tx=(x.innerText||'').trim();
        return tx && tx.toUpperCase().startsWith(tool);
      });
      if (!el) continue;
      if (el.querySelector && el.querySelector('[data-vsp-tool-verdict="1"]')) continue;

      const vv = by?.[tool]?.verdict || by?.[tool]?.status || '';
      const m = map(vv);

      // wrap text + badge without breaking layout
      const wrap=document.createElement('span');
      wrap.className='vsp-pill-v';
      wrap.innerHTML = `<span>${tool}</span> <span class="${m.c}" data-vsp-tool-verdict="1">${m.t}</span>`;
      el.innerHTML = '';
      el.appendChild(wrap);
      n++;
    }
    if (n) console.log(`[${TAG}] decorated tool pills:`, n);
  }

  async function boot(){
    ensureStyle();
    const rid=await resolveRID();
    if (!rid) return;
    const gs=await fetchGate(rid).catch(()=>null);
    if (!gs) return;
    decorateByTool(gs.by_tool || {});
  }

  if (document.readyState==='loading') document.addEventListener('DOMContentLoaded', boot, {once:true});
  else boot();
})();
