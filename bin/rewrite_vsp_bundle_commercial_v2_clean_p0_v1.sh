#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_commercial_v2.js"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_rewrite_clean_${TS}"
echo "[BACKUP] $F.bak_rewrite_clean_${TS}"

cat > "$F" <<'JS'
/* VSP_BUNDLE_COMMERCIAL_V2_CLEAN_P0_V1: clean, stable, no console-red */
(function(){
  'use strict';

  // ---------- tiny utils ----------
  const $  = (sel, root=document) => root.querySelector(sel);
  const $$ = (sel, root=document) => Array.from(root.querySelectorAll(sel));
  const sleep = (ms)=>new Promise(r=>setTimeout(r, ms));
  async function fetchJson(url){
    const r = await fetch(url, { cache:'no-store' });
    let j = null;
    try { j = await r.json(); } catch(_){}
    if(!r.ok) throw new Error('HTTP '+r.status);
    return j;
  }

  // ---------- toast ----------
  function ensureCss(){
    if($('#__vsp_clean_css')) return;
    const st=document.createElement('style');
    st.id='__vsp_clean_css';
    st.textContent = `
      .vspToast{ position:fixed; right:22px; bottom:360px; z-index:100000; padding:10px 12px;
        background:rgba(22,24,30,.96); border:1px solid rgba(255,255,255,.10);
        border-radius:12px; transform:translateY(10px); opacity:0; transition:all .18s ease;
        box-shadow:0 14px 35px rgba(0,0,0,.45); font-size:13px; color:#e9eef7; }
      .vspToast.on{ transform:translateY(0); opacity:1; }
      .vspToast.bad{ border-color: rgba(255,80,80,.35); }
      .vspToast.good{ border-color: rgba(80,255,160,.30); }
      #vspQuickActions{ position:fixed; right:18px; bottom:18px; z-index:99999; width:320px;
        background:linear-gradient(180deg, rgba(22,24,30,.95), rgba(16,18,24,.92));
        border:1px solid rgba(255,255,255,.10);
        border-radius:18px; box-shadow:0 18px 55px rgba(0,0,0,.55);
        backdrop-filter: blur(10px); overflow:hidden; color:#e9eef7; }
      #vspQuickActions .hd{ padding:12px 14px; display:flex; align-items:center; justify-content:space-between;
        border-bottom:1px solid rgba(255,255,255,.08); }
      #vspQuickActions .hd .t{ font-weight:850; font-size:12px; letter-spacing:.10em; opacity:.9; }
      #vspQuickActions .hd .pill{ font-size:11px; font-weight:750; padding:4px 8px; border-radius:999px;
        border:1px solid rgba(255,255,255,.12); background:rgba(255,255,255,.06); opacity:.9; }
      #vspQuickActions .hd .pill.ok{ border-color:rgba(80,255,160,.30); background:rgba(80,255,160,.10); }
      #vspQuickActions .hd .pill.bad{ border-color:rgba(255,80,80,.35); background:rgba(255,80,80,.10); }
      #vspQuickActions .hd .x{ cursor:pointer; opacity:.65; font-size:14px; }
      #vspQuickActions .hd .x:hover{ opacity:1; }
      #vspQuickActions .bd{ padding:12px 14px; display:grid; grid-template-columns:1fr; gap:10px; }
      #vspQuickActions button{ all:unset; cursor:pointer; padding:10px 12px; border-radius:12px;
        background:rgba(255,255,255,.06); border:1px solid rgba(255,255,255,.10);
        display:flex; align-items:center; justify-content:space-between; font-weight:760; font-size:13px; }
      #vspQuickActions button:hover{ background:rgba(255,255,255,.10); }
      #vspQuickActions .muted{ opacity:.72; font-weight:700; font-size:12px; }
      #vspQuickActions .meta{ display:flex; gap:8px; align-items:center; justify-content:space-between; }
      #vspQuickActions .rid{ font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size:11px; opacity:.85; }
      #vspQuickActions .copy{ all:unset; cursor:pointer; padding:6px 10px; border-radius:10px;
        border:1px solid rgba(255,255,255,.10); background:rgba(255,255,255,.06); font-size:12px; font-weight:750; }
      #vspQuickActions .copy:hover{ background:rgba(255,255,255,.10); }
      #vspQuickActions .status{ font-size:12px; opacity:.78; line-height:1.25; }
    `;
    document.head.appendChild(st);
  }
  function toast(msg, ok){
    ensureCss();
    const t=document.createElement('div');
    t.className='vspToast' + (ok===false?' bad':ok===true?' good':'');
    t.textContent=String(msg||'');
    document.body.appendChild(t);
    setTimeout(()=>t.classList.add('on'), 10);
    setTimeout(()=>t.classList.remove('on'), 2200);
    setTimeout(()=>{ try{t.remove();}catch(_){ } }, 2700);
  }

  // ---------- latest RID cache ----------
  let LATEST = { rid:'', run_dir:'' };
  async function refreshLatest(){
    try{
      const j = await fetchJson('/api/vsp/latest_rid_v1?ts=' + Date.now());
      LATEST.rid = j?.rid || '';
      LATEST.run_dir = j?.ci_run_dir || '';
      // update any header label that contains "RID:"
      const nodes = $$('*').filter(n=>{
        if(!n || !n.textContent) return false;
        const t = n.textContent.trim();
        return t.startsWith('RID:') || t.startsWith('RID(') || t.includes('RID: (none)') || t.includes('RID:');
      }).slice(0, 6);
      nodes.forEach(n=>{
        // keep short stable
        if(String(n.textContent||'').includes('RID')) n.textContent = 'RID: ' + (LATEST.rid || '(none)');
      });
      return LATEST;
    }catch(e){
      return LATEST;
    }
  }

  // ---------- drilldown safe (NEVER throw) ----------
  // Some parts call identifier directly, so sync both.
  function __VSP_DD_ART_CALL__(h, ...args){
    try{
      if(typeof h === 'function') return h(...args);
      if(h && typeof h.open === 'function') return h.open(...args);
      if(h && typeof h.install === 'function') return h.install(...args);
      if(h && typeof h.init === 'function') return h.init(...args);
    }catch(e){
      try{ console.warn('[VSP][DD_SAFE_CALL]', e); }catch(_){}
    }
    return null;
  }
  // Provide stable handler + keep window/identifier aligned.
  function installDrilldownStub(){
    const k='VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2';
    const fn = function(){ return null; };
    window[k]=fn;
    try{ VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = fn; }catch(_){}
    // keep in sync if overwritten later
    try{
      Object.defineProperty(window, k, {
        configurable:true,
        get(){ return fn; },
        set(nv){
          // always coerce to callable wrapper
          const wrapped = function(){ return __VSP_DD_ART_CALL__(nv, ...arguments); };
          window[k] = wrapped; // updates getter/setter? safe; but avoid recursion by redef later
          try{ VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = wrapped; }catch(_){}
        }
      });
    }catch(_){}
  }

  // ---------- tab router (soft) ----------
  const TABS = [
    { key:'dashboard',   pane:'#vsp-dashboard-main' },
    { key:'runs',        pane:'#vsp-runs-main' },
    { key:'datasource',  pane:'#vsp-datasource-main' },
    { key:'settings',    pane:'#vsp-settings-main' },
    { key:'rules',       pane:'#vsp-rules-main' },
  ];
  function showTab(key){
    for(const t of TABS){
      const el = $(t.pane);
      if(!el) continue;
      el.style.display = (t.key===key) ? '' : 'none';
    }
  }
  function normalizeHash(){
    const h = (location.hash||'').replace('#','').trim().toLowerCase();
    if(!h) return 'dashboard';
    if(h.startsWith('run')) return 'runs';
    if(h.startsWith('data')) return 'datasource';
    if(h.startsWith('set')) return 'settings';
    if(h.startsWith('rule')) return 'rules';
    if(h.startsWith('dash')) return 'dashboard';
    return 'dashboard';
  }
  function bindHashRouter(){
    window.addEventListener('hashchange', ()=>showTab(normalizeHash()));
    showTab(normalizeHash());
  }

  // ---------- header export buttons ----------
  function findHeaderButtons(){
    // find by button text (robust to DOM changes)
    const btns = $$('button');
    const byText = (txt)=>btns.find(b=>String(b.textContent||'').trim().toLowerCase()===txt);
    return {
      html: byText('export html'),
      zip:  byText('export zip') || byText('export tgz') || byText('export tar'),
      pdf:  byText('export pdf'),
    };
  }
  async function bindHeaderExports(){
    const b = findHeaderButtons();
    if(!b.html && !b.zip && !b.pdf) return;

    const resolve = async ()=>{
      await refreshLatest();
      if(!LATEST.run_dir) throw new Error('No ci_run_dir');
      return LATEST.run_dir;
    };

    if(b.html){
      b.html.onclick = async ()=>{
        try{
          const rd = await resolve();
          window.open('/api/vsp/open_report_html_v1?run_dir='+encodeURIComponent(rd)+'&ts='+(Date.now()), '_blank');
        }catch(e){ toast('Open HTML failed ❌', false); }
      };
    }
    if(b.zip){
      b.zip.onclick = async ()=>{
        try{
          const rd = await resolve();
          window.location.href = '/api/vsp/export_report_tgz_v1?run_dir='+encodeURIComponent(rd)+'&ts='+(Date.now());
        }catch(e){ toast('Export TGZ failed ❌', false); }
      };
    }
    if(b.pdf){
      // no PDF endpoint yet -> degrade gracefully
      b.pdf.onclick = async ()=>{
        toast('PDF not wired yet — opening HTML', true);
        try{
          const rd = await resolve();
          window.open('/api/vsp/open_report_html_v1?run_dir='+encodeURIComponent(rd)+'&ts='+(Date.now()), '_blank');
        }catch(e){ toast('Open HTML failed ❌', false); }
      };
    }
  }

  // ---------- Quick Actions panel ----------
  function setPill(pill, ok, text){
    pill.textContent = text || 'READY';
    pill.classList.remove('ok','bad');
    if(ok===true) pill.classList.add('ok');
    if(ok===false) pill.classList.add('bad');
  }
  function installQuickActions(){
    ensureCss();
    if($('#vspQuickActions')) return;

    const box=document.createElement('div'); box.id='vspQuickActions';
    const hd=document.createElement('div'); hd.className='hd';
    const title=document.createElement('div'); title.className='t'; title.textContent='QUICK ACTIONS';
    const pill=document.createElement('div'); pill.className='pill'; pill.textContent='BOOT';
    const close=document.createElement('div'); close.className='x'; close.textContent='✕';
    close.title='Hide'; close.onclick=()=>{ try{box.remove();}catch(_){ } };
    hd.appendChild(title); hd.appendChild(pill); hd.appendChild(close);

    const bd=document.createElement('div'); bd.className='bd';
    const meta=document.createElement('div'); meta.className='meta';
    const rid=document.createElement('div'); rid.className='rid'; rid.textContent='RID: (loading…)';
    const copy=document.createElement('button'); copy.className='copy'; copy.textContent='Copy';
    copy.onclick=async ()=>{
      try{
        await refreshLatest();
        if(!LATEST.rid){ toast('No RID ❌', false); return; }
        await navigator.clipboard.writeText(LATEST.rid);
        toast('Copied RID ✅', true);
      }catch(e){ toast('Copy failed ❌', false); }
    };
    meta.appendChild(rid); meta.appendChild(copy);

    const status=document.createElement('div'); status.className='status'; status.textContent='Status: idle';
    bd.appendChild(meta); bd.appendChild(status);

    const mkBtn=(label, hint)=>{
      const b=document.createElement('button');
      const l=document.createElement('span'); l.textContent=label;
      const r=document.createElement('span'); r.className='muted'; r.textContent=hint;
      b.appendChild(l); b.appendChild(r);
      return b;
    };

    const b1=mkBtn('Export TGZ','download');
    b1.onclick=async ()=>{
      try{
        status.textContent='Status: resolving latest…'; setPill(pill,null,'RESOLVE');
        await refreshLatest();
        rid.textContent='RID: ' + (LATEST.rid||'(none)');
        if(!LATEST.run_dir){ setPill(pill,false,'NO RUN'); status.textContent='Status: missing ci_run_dir'; return; }
        status.textContent='Status: packing & downloading…'; setPill(pill,null,'PACK');
        window.location.href='/api/vsp/export_report_tgz_v1?run_dir='+encodeURIComponent(LATEST.run_dir)+'&ts='+(Date.now());
        setTimeout(()=>{ setPill(pill,true,'READY'); status.textContent='Status: download triggered'; }, 800);
      }catch(e){ setPill(pill,false,'ERROR'); status.textContent='Status: export error'; }
    };

    const b2=mkBtn('Open HTML report','new tab');
    b2.onclick=async ()=>{
      try{
        status.textContent='Status: resolving latest…'; setPill(pill,null,'RESOLVE');
        await refreshLatest();
        rid.textContent='RID: ' + (LATEST.rid||'(none)');
        if(!LATEST.run_dir){ setPill(pill,false,'NO RUN'); status.textContent='Status: missing ci_run_dir'; return; }
        status.textContent='Status: opening…'; setPill(pill,null,'OPEN');
        window.open('/api/vsp/open_report_html_v1?run_dir='+encodeURIComponent(LATEST.run_dir)+'&ts='+(Date.now()), '_blank');
        setTimeout(()=>{ setPill(pill,true,'READY'); status.textContent='Status: opened'; }, 450);
      }catch(e){ setPill(pill,false,'ERROR'); status.textContent='Status: open error'; }
    };

    const b3=mkBtn('Verify SHA256','server');
    b3.onclick=async ()=>{
      try{
        status.textContent='Status: resolving latest…'; setPill(pill,null,'RESOLVE');
        await refreshLatest();
        rid.textContent='RID: ' + (LATEST.rid||'(none)');
        if(!LATEST.run_dir){ setPill(pill,false,'NO RUN'); status.textContent='Status: missing ci_run_dir'; return; }
        status.textContent='Status: verifying…'; setPill(pill,null,'VERIFY');
        const j = await fetchJson('/api/vsp/verify_report_sha_v1?run_dir='+encodeURIComponent(LATEST.run_dir)+'&ts='+(Date.now()));
        if(j && j.ok){ setPill(pill,true,'OK'); status.textContent='Status: SHA256 OK ✅'; toast('SHA256 OK ✅', true); }
        else { setPill(pill,false,'FAIL'); status.textContent='Status: SHA256 FAIL ❌'; toast('SHA256 FAIL ❌', false); }
      }catch(e){ setPill(pill,false,'ERROR'); status.textContent='Status: verify error'; toast('Verify error ❌', false); }
    };

    bd.appendChild(b1); bd.appendChild(b2); bd.appendChild(b3);

    box.appendChild(hd); box.appendChild(bd);
    document.body.appendChild(box);

    // initial refresh + periodic
    (async ()=>{
      await sleep(150);
      await refreshLatest();
      rid.textContent='RID: ' + (LATEST.rid||'(none)');
      setPill(pill,true,'READY');
      status.textContent='Status: ready';
    })();
    setInterval(async ()=>{ try{ await refreshLatest(); rid.textContent='RID: ' + (LATEST.rid||'(none)'); }catch(_){ } }, 15000);
  }

  // ---------- boot ----------
  function boot(){
    try{
      installDrilldownStub();
      bindHashRouter();
      bindHeaderExports();
      installQuickActions();
      console.log('[VSP_CLEAN_BUNDLE] installed');
    }catch(e){
      try{ console.warn('[VSP_CLEAN_BUNDLE] boot err', e); }catch(_){}
    }
  }

  if(document.readyState==='loading'){
    document.addEventListener('DOMContentLoaded', boot);
  }else{
    boot();
  }
})();
JS

echo "== node --check =="
node --check "$F"
echo "== restart 8910 =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh
echo "[NEXT] Ctrl+Shift+R. Console phải sạch, Quick Actions + Export header hoạt động."
