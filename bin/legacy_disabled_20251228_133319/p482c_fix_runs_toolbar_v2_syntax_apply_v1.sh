#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F_RUNS="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p482c_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0
command -v sudo >/dev/null 2>&1 || true

[ -f "$F_RUNS" ] || { echo "[ERR] missing $F_RUNS" | tee -a "$OUT/log.txt"; exit 2; }
cp -f "$F_RUNS" "${F_RUNS}.bak_p482c_${TS}"
echo "[OK] backup => ${F_RUNS}.bak_p482c_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path

p=Path("static/js/vsp_c_runs_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK_BAD="VSP_P482B_RUNS_TOOLBAR_V2_FOR_LIST_V1"
MARK_GOOD="VSP_P482C_RUNS_TOOLBAR_V2_LIST_OK_V1"

# 1) remove bad P482b block (best-effort)
if MARK_BAD in s:
    i = s.find(MARK_BAD)
    # remove from nearest /* before MARK to the nearest "})();" after MARK
    start = s.rfind("/*", 0, i)
    if start < 0: start = i
    end = s.find("})();", i)
    if end >= 0:
        end = end + len("})();")
        s = s[:start] + "\n/* [P482c] removed bad P482b block */\n" + s[end:]
        print("[OK] removed bad P482b block")
    else:
        # fallback: just remove the marker line
        s = s.replace(MARK_BAD, "[REMOVED_"+MARK_BAD+"]")
        print("[WARN] could not find end of IIFE; marker replaced")

# 2) if already patched P482c, skip append
if MARK_GOOD in s:
    p.write_text(s, encoding="utf-8")
    print("[OK] P482c already present")
else:
    js = r"""
/* VSP_P482C_RUNS_TOOLBAR_V2_LIST_OK_V1
 * Runs tab: list rows (has button 'Use RID'). Add toolbar V2 + hide legacy controls.
 */
(function(){
  function onReady(fn){
    if(document.readyState === 'complete' || document.readyState === 'interactive') return fn();
    document.addEventListener('DOMContentLoaded', fn, {once:true});
  }

  function injectCss(){
    if(document.getElementById('vsp-runs-toolbar-v2-css')) return;
    var st=document.createElement('style');
    st.id='vsp-runs-toolbar-v2-css';
    st.textContent =
      ".vsp-runs-toolbar-v2{display:flex;gap:8px;align-items:center;flex-wrap:wrap;padding:10px 12px;margin:10px 0 12px 0;border:1px solid rgba(255,255,255,.08);background:rgba(0,0,0,.18);border-radius:12px;position:sticky;top:10px;z-index:20;backdrop-filter:blur(10px);}"+
      ".vsp-runs-toolbar-v2 input,.vsp-runs-toolbar-v2 select{height:32px;border-radius:10px;border:1px solid rgba(255,255,255,.10);background:rgba(0,0,0,.25);color:#dfe7ff;padding:0 10px;outline:none;}"+
      ".vsp-runs-toolbar-v2 input{min-width:260px;}"+
      ".vsp-runs-toolbar-v2 .btn{height:32px;padding:0 10px;border-radius:10px;border:1px solid rgba(255,255,255,.12);background:rgba(0,0,0,.22);color:#dfe7ff;cursor:pointer;}"+
      ".vsp-runs-toolbar-v2 .btn:hover{border-color:rgba(255,255,255,.22);}"+
      ".vsp-runs-toolbar-v2 .hint{opacity:.75;font-size:12px;margin-left:auto;}"+
      ".vsp-hide-legacy{display:none !important;}";
    document.head.appendChild(st);
  }

  function findRunsPanel(){
    var nodes=[].slice.call(document.querySelectorAll('h1,h2,h3,div,span'));
    for(var i=0;i<nodes.length;i++){
      var t=(nodes[i].textContent||'').trim();
      if(/Runs\s*&\s*Reports/i.test(t) || /^Runs$/i.test(t)){
        return nodes[i].closest('section,article,div') || nodes[i].parentElement || document.body;
      }
    }
    return document.querySelector('#app') || document.querySelector('.vsp-page') || document.body;
  }

  function hideLegacy(panel){
    // Hide old search/export bars if they exist
    var els=[].slice.call(panel.querySelectorAll('button,input,select,div,span'));
    for(var i=0;i<els.length;i++){
      var el=els[i];
      var txt=((el.textContent||'')+'').trim();
      var ph=(el.getAttribute && el.getAttribute('placeholder')) ? el.getAttribute('placeholder') : '';
      if(/Open\s+Exports/i.test(txt) || /Open\s+Exports/i.test(ph) || /Search\s+RID/i.test(ph) || /Search\s+RID/i.test(txt)){
        var box=el.closest('div,section,article') || el;
        box.classList.add('vsp-hide-legacy');
      }
    }
  }

  function uniq(arr){
    var out=[], seen=new Set();
    for(var i=0;i<arr.length;i++){
      var x=arr[i];
      if(x && !seen.has(x)){ seen.add(x); out.push(x); }
    }
    return out;
  }

  function closestRow(btn){
    // prefer smaller containers: try known row tags/classes first
    return btn.closest('tr,[role="row"],li,.vsp-run-row,.run-row') ||
           btn.closest('div') ||
           btn.parentElement;
  }

  function getRows(panel){
    var btns=[].slice.call(panel.querySelectorAll('button')).filter(function(b){
      return /Use\s*RID/i.test((b.textContent||''));
    });
    if(btns.length){
      var rows=btns.map(closestRow);
      return uniq(rows);
    }
    return [];
  }

  function parseRid(text){
    var m=(text||'').match(/\b(VSP[_-][A-Za-z0-9_:-]+)\b/);
    return m ? m[1] : '';
  }
  function parseDate(text){
    var m=(text||'').match(/\b(20\d{2}-\d{2}-\d{2})\b/);
    return m ? m[1] : '';
  }
  function parseStatus(text){
    var tx=((text||'')+'').toUpperCase();
    if(tx.indexOf('DEGRADED')>=0) return 'DEGRADED';
    if(tx.indexOf('RUNNING')>=0) return 'RUNNING';
    if(tx.indexOf('FAIL')>=0) return 'FAIL';
    if(tx.indexOf('OK')>=0) return 'OK';
    if(tx.indexOf('UNKNOWN')>=0) return 'UNKNOWN';
    return 'UNKNOWN';
  }

  function ensureToolbar(panel){
    if(panel.querySelector('.vsp-runs-toolbar-v2')) return;

    var bar=document.createElement('div');
    bar.className='vsp-runs-toolbar-v2';

    var q=document.createElement('input');
    q.type='text';
    q.placeholder='Filter (RID / date / status)…';

    var st=document.createElement('select');
    st.innerHTML =
      '<option value="">Status: ALL</option>'+
      '<option value="OK">OK</option>'+
      '<option value="FAIL">FAIL</option>'+
      '<option value="DEGRADED">DEGRADED</option>'+
      '<option value="RUNNING">RUNNING</option>'+
      '<option value="UNKNOWN">UNKNOWN</option>';

    var sort=document.createElement('select');
    sort.innerHTML =
      '<option value="newest">Sort: Newest</option>'+
      '<option value="oldest">Sort: Oldest</option>'+
      '<option value="rid_asc">Sort: RID A→Z</option>'+
      '<option value="rid_desc">Sort: RID Z→A</option>';

    var btnClear=document.createElement('button');
    btnClear.className='btn';
    btnClear.textContent='Clear';

    var btnRefresh=document.createElement('button');
    btnRefresh.className='btn';
    btnRefresh.textContent='Refresh';

    var hint=document.createElement('div');
    hint.className='hint';
    hint.textContent='rows: 0';

    bar.appendChild(q);
    bar.appendChild(st);
    bar.appendChild(sort);
    bar.appendChild(btnClear);
    bar.appendChild(btnRefresh);
    bar.appendChild(hint);

    // place at top of panel
    var host = panel.querySelector('div,section,article') || panel;
    host.insertBefore(bar, host.firstChild);

    function apply(){
      var rows=getRows(panel);
      var needle=(q.value||'').trim().toLowerCase();
      var want=(st.value||'').trim().toUpperCase();

      var visible=[];
      for(var i=0;i<rows.length;i++){
        var r=rows[i];
        var tx=(r && r.textContent) ? r.textContent : '';
        var rid=parseRid(tx);
        var dt=parseDate(tx);
        var status=parseStatus(tx);
        var hay=(tx+' '+rid+' '+dt+' '+status).toLowerCase();

        var ok=true;
        if(needle && hay.indexOf(needle)<0) ok=false;
        if(want && status!==want) ok=false;

        r.style.display = ok ? '' : 'none';
        if(ok) visible.push(r);
      }

      // sort visible
      var mode=sort.value||'newest';
      visible.sort(function(a,b){
        var ta=(a.textContent||'');
        var tb=(b.textContent||'');
        var ra=parseRid(ta).toLowerCase();
        var rb=parseRid(tb).toLowerCase();
        var da=parseDate(ta) || '';
        var db=parseDate(tb) || '';
        if(mode==='rid_asc') return ra.localeCompare(rb);
        if(mode==='rid_desc') return rb.localeCompare(ra);
        if(mode==='oldest') return da.localeCompare(db);
        // newest default
        return db.localeCompare(da);
      });

      // re-append in best parent
      if(visible.length){
        var count=new Map();
        for(var i=0;i<visible.length;i++){
          var p=visible[i].parentElement;
          if(!p) continue;
          count.set(p, (count.get(p)||0)+1);
        }
        var best=null, bestN=0;
        count.forEach(function(v,k){ if(v>bestN){bestN=v; best=k;} });
        if(best){
          for(var i=0;i<visible.length;i++){
            try{ best.appendChild(visible[i]); }catch(e){}
          }
        }
      }

      hint.textContent = 'rows: '+visible.length+'/'+rows.length;
    }

    q.addEventListener('input', apply);
    st.addEventListener('change', apply);
    sort.addEventListener('change', apply);
    btnClear.addEventListener('click', function(){
      q.value=''; st.value=''; sort.value='newest'; apply();
    });
    btnRefresh.addEventListener('click', function(){
      // try click an existing refresh button in the panel
      var bs=[].slice.call(panel.querySelectorAll('button'));
      var b=null;
      for(var i=0;i<bs.length;i++){
        if(bs[i]!==btnRefresh && /refresh/i.test((bs[i].textContent||''))){ b=bs[i]; break; }
      }
      if(b) b.click(); else location.reload();
    });

    setTimeout(apply, 200);
    setTimeout(apply, 900);
    console.log('[P482c] runs toolbar V2 ready');
  }

  onReady(function(){
    injectCss();
    var panel=findRunsPanel();
    hideLegacy(panel);
    ensureToolbar(panel);
  });
})();
"""
    s = s.rstrip() + "\n\n" + js + "\n"
    p.write_text(s, encoding="utf-8")
    print("[OK] appended P482c block")
PY

if [ "${HAS_NODE}" = "1" ]; then
  echo "== node --check vsp_c_runs_v1.js ==" | tee -a "$OUT/log.txt"
  if ! node --check "$F_RUNS" 2>&1 | tee -a "$OUT/log.txt" ; then
    echo "[ERR] node --check failed (see log)" | tee -a "$OUT/log.txt"
    exit 2
  fi
  echo "[OK] node --check ok" | tee -a "$OUT/log.txt"
else
  echo "[WARN] node not found; skip syntax check" | tee -a "$OUT/log.txt"
fi

echo "[INFO] restart ${SVC}" | tee -a "$OUT/log.txt"
sudo systemctl restart "$SVC" 2>/dev/null || true
systemctl is-active "$SVC" 2>/dev/null || true

echo "[OK] P482c done. Close tab /c/runs, reopen then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
