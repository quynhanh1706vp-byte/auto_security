#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_commercial_v2.js"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_quick_polish_${TS}"
echo "[BACKUP] $F.bak_quick_polish_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("/home/test/Data/SECURITY_BUNDLE/ui/static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_QUICK_ACTIONS_EXPORT_UI_P0_V3"
if MARK in s:
    print("[OK] already patched", MARK)
    raise SystemExit(0)

block = r'''
/* {MARK}: polish quick actions (RID badge + status + copy + live refresh) */
(function(){
  'use strict';
  if (window.__{MARK}__) return;
  window.__{MARK}__ = true;

  function css(txt){
    var st=document.createElement('style');
    st.setAttribute('data-vsp','{MARK}');
    st.appendChild(document.createTextNode(txt));
    document.head.appendChild(st);
  }
  function el(tag, cls, html){
    var e=document.createElement(tag);
    if(cls) e.className=cls;
    if(html!=null) e.innerHTML=html;
    return e;
  }
  function toast(msg, ok){
    var t=el('div','vspToast', msg);
    if(ok===false) t.classList.add('bad');
    if(ok===true) t.classList.add('good');
    document.body.appendChild(t);
    setTimeout(function(){ t.classList.add('on'); }, 10);
    setTimeout(function(){ t.classList.remove('on'); }, 2200);
    setTimeout(function(){ try{t.remove();}catch(_){ } }, 2700);
  }

  css(`
    #vspQuickActions{ position:fixed; right:18px; bottom:18px; z-index:99999; width:320px;
      background:linear-gradient(180deg, rgba(22,24,30,.95), rgba(16,18,24,.92));
      border:1px solid rgba(255,255,255,.10);
      border-radius:18px; box-shadow:0 18px 55px rgba(0,0,0,.55);
      backdrop-filter: blur(10px); overflow:hidden; }
    #vspQuickActions .hd{ padding:12px 14px; display:flex; align-items:center; justify-content:space-between;
      border-bottom:1px solid rgba(255,255,255,.08); }
    #vspQuickActions .hd .t{ font-weight:850; font-size:12px; letter-spacing:.10em; opacity:.9; }
    #vspQuickActions .hd .pill{ font-size:11px; font-weight:750; padding:4px 8px; border-radius:999px;
      border:1px solid rgba(255,255,255,.12); background:rgba(255,255,255,.06); opacity:.9; }
    #vspQuickActions .hd .pill.ok{ border-color:rgba(80,255,160,.30); background:rgba(80,255,160,.10); }
    #vspQuickActions .hd .pill.bad{ border-color:rgba(255,80,80,.35); background:rgba(255,80,80,.10); }
    #vspQuickActions .bd{ padding:12px 14px; display:grid; grid-template-columns:1fr; gap:10px; }
    #vspQuickActions button{ all:unset; cursor:pointer; padding:10px 12px; border-radius:12px;
      background:rgba(255,255,255,.06); border:1px solid rgba(255,255,255,.10);
      display:flex; align-items:center; justify-content:space-between; font-weight:760; font-size:13px; }
    #vspQuickActions button:hover{ background:rgba(255,255,255,.10); }
    #vspQuickActions .muted{ opacity:.72; font-weight:700; font-size:12px; }
    #vspQuickActions .x{ cursor:pointer; opacity:.65; font-size:14px; }
    #vspQuickActions .x:hover{ opacity:1; }
    #vspQuickActions .meta{ display:flex; gap:8px; align-items:center; justify-content:space-between; }
    #vspQuickActions .rid{ font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size:11px; opacity:.85; }
    #vspQuickActions .copy{ all:unset; cursor:pointer; padding:6px 10px; border-radius:10px;
      border:1px solid rgba(255,255,255,.10); background:rgba(255,255,255,.06); font-size:12px; font-weight:750; }
    #vspQuickActions .copy:hover{ background:rgba(255,255,255,.10); }
    #vspQuickActions .status{ font-size:12px; opacity:.78; line-height:1.25; }
    .vspToast{ position:fixed; right:22px; bottom:360px; z-index:100000; padding:10px 12px;
      background:rgba(22,24,30,.96); border:1px solid rgba(255,255,255,.10);
      border-radius:12px; transform:translateY(10px); opacity:0; transition:all .18s ease;
      box-shadow:0 14px 35px rgba(0,0,0,.45); font-size:13px; }
    .vspToast.on{ transform:translateY(0); opacity:1; }
    .vspToast.bad{ border-color: rgba(255,80,80,.35); }
    .vspToast.good{ border-color: rgba(80,255,160,.30); }
  `);

  async function getLatest(){
    var r = await fetch('/api/vsp/latest_rid_v1?ts=' + Date.now(), {cache:'no-store'});
    var j = await r.json();
    return { rid: j.rid || '', run_dir: j.ci_run_dir || '' };
  }

  function setPill(pill, ok, text){
    pill.textContent = text || 'LATEST';
    pill.classList.remove('ok','bad');
    if(ok===true) pill.classList.add('ok');
    if(ok===false) pill.classList.add('bad');
  }

  function install(){
    if(document.getElementById('vspQuickActions')) return;

    var box=el('div','',null); box.id='vspQuickActions';

    var hd=el('div','hd',null);
    hd.appendChild(el('div','t','QUICK ACTIONS'));
    var pill=el('div','pill','LATEST'); hd.appendChild(pill);
    var close=el('div','x','✕'); close.title='Hide'; close.onclick=function(){ try{box.remove();}catch(_){ } };
    hd.appendChild(close);

    var bd=el('div','bd',null);

    var meta=el('div','meta',null);
    var rid=el('div','rid','RID: (loading…)');
    var copy=el('button','copy','Copy');
    copy.onclick=async function(){
      try{
        var x = await getLatest();
        if(!x.rid){ toast('No RID ❌', false); return; }
        await navigator.clipboard.writeText(x.rid);
        toast('Copied RID ✅', true);
      }catch(e){ toast('Copy failed ❌', false); }
    };
    meta.appendChild(rid); meta.appendChild(copy);

    var status=el('div','status','Status: idle');
    bd.appendChild(meta);
    bd.appendChild(status);

    var b1=el('button','', '<span>Export TGZ</span><span class="muted">download</span>');
    b1.onclick=async function(){
      try{
        status.textContent='Status: resolving latest RID…';
        setPill(pill, null, 'RESOLVE');
        var x = await getLatest();
        if(!x.run_dir){ setPill(pill,false,'NO RUN'); status.textContent='Status: missing ci_run_dir'; toast('No ci_run_dir ❌', false); return; }
        rid.textContent='RID: ' + (x.rid || '(unknown)');
        status.textContent='Status: packing & downloading…';
        setPill(pill, null, 'PACK');
        window.location.href='/api/vsp/export_report_tgz_v1?run_dir='+encodeURIComponent(x.run_dir)+'&ts='+(Date.now());
        setTimeout(function(){ setPill(pill,true,'READY'); status.textContent='Status: download triggered'; }, 900);
      }catch(e){ setPill(pill,false,'ERROR'); status.textContent='Status: export error'; toast('Export error ❌', false); }
    };

    var b2=el('button','', '<span>Open HTML report</span><span class="muted">new tab</span>');
    b2.onclick=async function(){
      try{
        status.textContent='Status: resolving latest RID…';
        setPill(pill, null, 'RESOLVE');
        var x = await getLatest();
        if(!x.run_dir){ setPill(pill,false,'NO RUN'); status.textContent='Status: missing ci_run_dir'; toast('No ci_run_dir ❌', false); return; }
        rid.textContent='RID: ' + (x.rid || '(unknown)');
        status.textContent='Status: opening report…';
        setPill(pill, null, 'OPEN');
        window.open('/api/vsp/open_report_html_v1?run_dir='+encodeURIComponent(x.run_dir)+'&ts='+(Date.now()), '_blank');
        setTimeout(function(){ setPill(pill,true,'READY'); status.textContent='Status: opened'; }, 500);
      }catch(e){ setPill(pill,false,'ERROR'); status.textContent='Status: open error'; toast('Open error ❌', false); }
    };

    var b3=el('button','', '<span>Verify SHA256</span><span class="muted">server</span>');
    b3.onclick=async function(){
      try{
        status.textContent='Status: resolving latest RID…';
        setPill(pill, null, 'RESOLVE');
        var x = await getLatest();
        if(!x.run_dir){ setPill(pill,false,'NO RUN'); status.textContent='Status: missing ci_run_dir'; toast('No ci_run_dir ❌', false); return; }
        rid.textContent='RID: ' + (x.rid || '(unknown)');
        status.textContent='Status: verifying SHA256…';
        setPill(pill, null, 'VERIFY');
        var r=await fetch('/api/vsp/verify_report_sha_v1?run_dir='+encodeURIComponent(x.run_dir)+'&ts='+(Date.now()), {cache:'no-store'});
        var j=await r.json().catch(()=>({ok:false}));
        if(j.ok){ setPill(pill,true,'OK'); status.textContent='Status: SHA256 OK ✅'; toast('SHA256 OK ✅', true); }
        else { setPill(pill,false,'FAIL'); status.textContent='Status: SHA256 FAIL ❌'; toast('SHA256 FAIL ❌', false); }
      }catch(e){ setPill(pill,false,'ERROR'); status.textContent='Status: verify error'; toast('Verify error ❌', false); }
    };

    bd.appendChild(b1); bd.appendChild(b2); bd.appendChild(b3);

    box.appendChild(hd); box.appendChild(bd);
    document.body.appendChild(box);

    // initial refresh
    (async function(){
      try{
        var x=await getLatest();
        rid.textContent='RID: ' + (x.rid || '(unknown)');
        setPill(pill, true, 'READY');
        status.textContent='Status: ready';
      }catch(e){
        setPill(pill, false, 'ERROR');
        status.textContent='Status: cannot read latest_rid_v1';
      }
    })();

    // periodic refresh (light)
    setInterval(async function(){
      try{
        var x=await getLatest();
        if(x && x.rid){ rid.textContent='RID: ' + x.rid; }
      }catch(_){}
    }, 15000);
  }

  if(document.readyState==='loading'){
    document.addEventListener('DOMContentLoaded', install);
  } else {
    install();
  }
})();
'''.replace("{MARK}", MARK)

# append at end
s = s.rstrip() + "\n\n" + block + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended", MARK)
PY

echo "== node --check =="
node --check "$F"

echo "== restart 8910 =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh

echo "[NEXT] Ctrl+Shift+R. Panel sẽ có RID badge + status + Copy."
