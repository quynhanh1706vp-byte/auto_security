#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_tabs5_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p963i_${TS}"
mkdir -p "$OUT"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "$OUT/$(basename "$F").bak_${TS}"
echo "[OK] backup => $OUT"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
marker="/* VSP_P963I_KPI_V2 */"
if marker in s:
    print("[OK] P963I already applied")
    raise SystemExit(0)

addon = r'''
''' + marker + r'''
;(function(){
  try{
    function ridFromURL(){
      try{
        var sp=new URLSearchParams(location.search||'');
        return String(sp.get('rid')||sp.get('RID')||'').trim();
      }catch(e){ return ''; }
    }
    function setText(sel,v){ var el=document.querySelector(sel); if(!el) return false; el.textContent=String(v); return true; }

    function updateKPIs(counts){
      var total=0;
      ['CRITICAL','HIGH','MEDIUM','LOW','INFO','TRACE'].forEach(function(k){ total += (counts[k]||0); });

      // common ids
      setText('#kpi_total', total);
      setText('#kpi_critical', counts.CRITICAL||0);
      setText('#kpi_high', counts.HIGH||0);
      setText('#kpi_medium', counts.MEDIUM||0);
      setText('#kpi_low', counts.LOW||0);
      setText('#kpi_info', counts.INFO||0);
      setText('#kpi_trace', counts.TRACE||0);

      // data attrs
      ['TOTAL','CRITICAL','HIGH','MEDIUM','LOW','INFO','TRACE'].forEach(function(k){
        var v=(k==='TOTAL')?total:(counts[k]||0);
        var el=document.querySelector('[data-kpi="'+k+'"],[data-kpi-key="'+k+'"],[data-sev="'+k+'"]');
        if(el) el.textContent=String(v);
      });

      // fallback: KPI cards by label text
      var map={TOTAL:total,CRITICAL:counts.CRITICAL||0,HIGH:counts.HIGH||0,MEDIUM:counts.MEDIUM||0,LOW:counts.LOW||0,INFO:counts.INFO||0,TRACE:counts.TRACE||0};
      Object.keys(map).forEach(function(k){
        var nodes=document.querySelectorAll('.kpi,label,span,div,strong,b,h3,h4');
        for(var i=0;i<nodes.length;i++){
          var t=(nodes[i].textContent||'').trim().toUpperCase();
          if(t===k){
            var box=nodes[i].closest('.kpi-card,.card,.box,.panel') || nodes[i].parentElement;
            if(!box) continue;
            var num=box.querySelector('.kpi-num,.num,.value,strong,b,span');
            if(num){ num.textContent=String(map[k]); break; }
          }
        }
      });
    }

    function ensureCioBlock(counts, meta){
      var root=document.getElementById('vsp_cio_kpi_root');
      if(!root){
        // create a visible block under the top area
        root=document.createElement('div');
        root.id='vsp_cio_kpi_root';
        root.style.cssText="margin:10px 0;padding:10px;border:1px solid rgba(255,255,255,.08);border-radius:10px";
        var host=document.querySelector('#main,.main,.content,body') || document.body;
        host.insertBefore(root, host.firstChild);
      }
      root.innerHTML='';
      var h=document.createElement('div');
      h.innerHTML='<b>CIO KPI (v2)</b> rid=<code>'+meta.rid+'</code> n='+meta.n;
      root.appendChild(h);

      var g=document.createElement('div');
      g.style.cssText="display:flex;gap:8px;flex-wrap:wrap;margin-top:8px";
      ['CRITICAL','HIGH','MEDIUM','LOW','INFO','TRACE'].forEach(function(k){
        var c=document.createElement('div');
        c.style.cssText="min-width:140px;flex:1;padding:10px;border-radius:10px;background:rgba(255,255,255,.03);cursor:pointer";
        c.innerHTML='<div style="opacity:.8;font-size:12px">'+k+'</div><div style="font-size:22px;font-weight:700">'+(counts[k]||0)+'</div>';
        c.onclick=function(){ location.href='/data_source?severity='+encodeURIComponent(k); };
        g.appendChild(c);
      });
      root.appendChild(g);
    }

    function run(){
      var rid=ridFromURL();
      if(!rid) return; // chỉ chạy khi bạn truyền rid (đúng như bạn đang làm)
      fetch('/api/vsp/kpi_counts_v2?rid='+encodeURIComponent(rid), {credentials:'same-origin'})
        .then(function(r){ return r.json(); })
        .then(function(j){
          console.log('[P963I] KPI v2', j);
          if(!j || !j.ok) return;
          updateKPIs(j.counts||{});
          ensureCioBlock(j.counts||{}, {rid: rid, n: j.n||0});
        })
        .catch(function(e){ console.warn('[P963I] KPI v2 fetch failed', e); });
    }

    if(document.readyState==='loading') document.addEventListener('DOMContentLoaded', run);
    else run();
  }catch(e){
    console.warn('[P963I] init error', e);
  }
})(); 
'''
p.write_text(s + "\n" + addon, encoding="utf-8")
print("[OK] appended P963I into bundle tabs5")
PY

echo "== restart+wait =="
sudo -v || true
sudo systemctl restart "$SVC" || true
VSP_UI_BASE="$BASE" MAX_WAIT=45 bash bin/ops/ops_restart_wait_ui_v1.sh

echo "[PASS] P963I applied. Open /vsp5?rid=... then Ctrl+Shift+R and check console for [P963I] KPI v2"
