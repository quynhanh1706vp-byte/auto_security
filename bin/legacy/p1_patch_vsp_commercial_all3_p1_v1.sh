#!/usr/bin/env bash
MARK="VSP_P1_POLISH_ALL3_V1"
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need date; need python3
command -v node >/dev/null 2>&1 && HAVE_NODE=1 || HAVE_NODE=0

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_all3_${TS}"
echo "[BACKUP] ${JS}.bak_all3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_POLISH_ALL3_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

patch = r"""
/* === VSP_P1_POLISH_ALL3_V1 (nav dedupe + pagination default + mismatch fixes) === */
(function(){
  'use strict';
  const MARK = 'VSP_P1_POLISH_ALL3_V1';

  // ---- logOnce / warnOnce (avoid console spam) ----
  const __once = new Set();
  function logOnce(k, ...a){ if(__once.has(k)) return; __once.add(k); try{ console.log('[VSP][P1]', ...a); }catch(_){ } }
  function warnOnce(k, ...a){ if(__once.has(k)) return; __once.add(k); try{ console.warn('[VSP][P1]', ...a); }catch(_){ } }

  // ---- helper: find elements by exact-ish text ----
  function elsByText(tagList, text){
    const out=[];
    const tags = tagList.split(',').map(x=>x.trim()).filter(Boolean);
    for(const t of tags){
      document.querySelectorAll(t).forEach(el=>{
        const tx=(el.textContent||'').trim();
        if(tx===text) out.push(el);
      });
    }
    return out;
  }

  // ---- 1) NAV DEDUPE (hide duplicate secondary nav buttons) ----
  function navDedupe(){
    try{
      const labels = ['Data Source','Settings','Rule Overrides','Runs & Reports','Dashboard'];
      for(const lab of labels){
        const hits = elsByText('a,button,div,span', lab);
        if(hits.length > 1){
          // keep first visible occurrence; hide later ones (usually inside big hero panel)
          for(let i=1;i<hits.length;i++){
            const el = hits[i];
            // don't hide top-left small "VSP" area etc; only hide if it's a big pill/button container
            const box = el.closest('a,button,[role="button"],.btn,.pill,.tab,.nav-item,div');
            const tgt = box || el;
            tgt.style.display = 'none';
          }
        }
      }
      logOnce(MARK+':nav', 'nav dedupe applied');
    }catch(e){
      warnOnce(MARK+':naverr', 'nav dedupe error', e);
    }
  }

  // ---- 2) PAGINATION / LIMIT DEFAULT (runs + findings) ----
  function patchFetchLimit(){
    if(window.__vsp_fetch_patched_all3) return;
    window.__vsp_fetch_patched_all3 = true;

    const origFetch = window.fetch.bind(window);
    window.fetch = async function(input, init){
      try{
        let url = (typeof input === 'string') ? input : (input && input.url) ? input.url : '';
        if(typeof url === 'string' && url){
          const isRuns = url.includes('/api/vsp/runs');
          const isFindings = url.includes('/api/vsp/findings') || url.includes('/api/vsp/unified') || url.includes('/api/vsp/data_source');
          if(isRuns || isFindings){
            // normalize limit: if missing -> 50; if limit=1 -> 50
            const hasQ = url.includes('?');
            const hasLimit = /[?&]limit=\d+/i.test(url);
            if(!hasLimit){
              url = url + (hasQ ? '&' : '?') + 'limit=50';
            }else{
              url = url.replace(/([?&]limit=)(1)(\b)/i, '$150$3');
            }
            if(typeof input !== 'string'){
              // rebuild Request
              input = new Request(url, input);
            }else{
              input = url;
            }
          }
        }
      }catch(_){ /* best effort */ }
      return origFetch(input, init);
    };

    logOnce(MARK+':fetch', 'fetch limit patched (runs/findings default limit=50)');
  }

  // ---- 2b) SHOW "Showing X of TOTAL" badges (Runs & Reports + Findings) ----
  function addShowingBadges(){
    // Runs
    function ensureBadgeRuns(){
      const hdr = Array.from(document.querySelectorAll('*')).find(el => (el.textContent||'').trim()==='Runs & Reports');
      if(!hdr) return;
      if(document.getElementById('vsp_p1_runs_showing_badge')) return;

      const b=document.createElement('div');
      b.id='vsp_p1_runs_showing_badge';
      b.style.fontSize='12px';
      b.style.opacity='0.85';
      b.style.marginTop='6px';
      b.textContent='Showing …';
      hdr.parentElement && hdr.parentElement.appendChild(b);

      const mo=new MutationObserver(()=>{
        try{
          // count rows in runs table (best-effort)
          const rows = document.querySelectorAll('table tbody tr').length || 0;
          // read TOTAL RUNS KPI if present
          let total = '';
          const kpi = Array.from(document.querySelectorAll('*')).find(el => (el.textContent||'').trim()==='TOTAL RUNS');
          if(kpi){
            // next numbers often near it
            const box = kpi.closest('div') || kpi.parentElement;
            const num = box ? (box.textContent||'').match(/TOTAL RUNS\s*([0-9][0-9,]*)/i) : None;
          }
          // fallback: search any big number near TOTAL RUNS
          if(!total){
            const cand = Array.from(document.querySelectorAll('*')).find(el => /TOTAL RUNS/i.test(el.textContent||''));
            if(cand){
              const m=(cand.textContent||'').match(/TOTAL RUNS\s*([0-9][0-9,]*)/i);
              if(m) total=m[1];
            }
          }
          b.textContent = total ? `Showing ${rows} of ${total}` : `Showing ${rows}`;
        }catch(_){}
      });
      mo.observe(document.body, {subtree:true, childList:true, characterData:true});
    }

    // Findings (Data Source)
    function ensureBadgeFindings(){
      const hdr = Array.from(document.querySelectorAll('*')).find(el => (el.textContent||'').trim()==='Unified Findings');
      if(!hdr) return;
      if(document.getElementById('vsp_p1_findings_showing_badge')) return;

      const b=document.createElement('div');
      b.id='vsp_p1_findings_showing_badge';
      b.style.fontSize='12px';
      b.style.opacity='0.85';
      b.style.marginTop='6px';
      b.textContent='Showing …';
      hdr.parentElement && hdr.parentElement.appendChild(b);

      const mo=new MutationObserver(()=>{
        try{
          const tables = document.querySelectorAll('table');
          let rows=0;
          tables.forEach(t=>{
            const h=(t.parentElement && t.parentElement.textContent||'');
            if(/Unified Findings/i.test(h)) rows = Math.max(rows, t.querySelectorAll('tbody tr').length);
          });
          b.textContent = `Showing ${rows} (limit auto=50)`;
        }catch(_){}
      });
      mo.observe(document.body, {subtree:true, childList:true, characterData:true});
    }

    ensureBadgeRuns();
    ensureBadgeFindings();
  }

  // ---- 3) FIX DASHBOARD donut mismatch: show "sample / total" ----
  function fixDonutTotal(){
    try{
      // read TOTAL FINDINGS number
      let totalFindings = '';
      const tf = Array.from(document.querySelectorAll('*')).find(el => (el.textContent||'').trim()==='TOTAL FINDINGS');
      if(tf){
        const box = tf.closest('div') || tf.parentElement;
        const m = (box ? (box.textContent||'') : '').match(/TOTAL FINDINGS\s*([0-9][0-9,]*)/i);
        if(m) totalFindings = m[1].replace(/,/g,'');
      }
      if(!totalFindings){
        // fallback search
        const cand = Array.from(document.querySelectorAll('*')).find(el => /TOTAL FINDINGS/i.test(el.textContent||''));
        if(cand){
          const m = (cand.textContent||'').match(/TOTAL FINDINGS\s*([0-9][0-9,]*)/i);
          if(m) totalFindings = m[1].replace(/,/g,'');
        }
      }
      if(!totalFindings) return;

      // find donut center text that contains "total"
      const totalNodes = Array.from(document.querySelectorAll('*'))
        .filter(el => el.children.length===0 && /total/i.test((el.textContent||'').trim()))
        .slice(0,80);

      // pick a node that has like "2500" and "total"
      let center = null;
      for(const el of totalNodes){
        const tx=(el.textContent||'').trim();
        if(/\b\d+\b/.test(tx) && /\btotal\b/i.test(tx)){
          center = el;
          break;
        }
      }
      if(!center) return;

      const tx=(center.textContent||'').trim();
      const m=tx.match(/(\d[\d,]*)\s*total/i);
      if(!m) return;
      const sample = m[1].replace(/,/g,'');

      center.textContent = `${sample} sample / ${totalFindings} total`;
      logOnce(MARK+':donut', 'donut total patched', {sample, total: totalFindings});
    }catch(e){
      warnOnce(MARK+':donuterr','donut patch error', e);
    }
  }

  // ---- 3b) FIX Rule Overrides mismatch: compute overrides count from editor; sync table if missing ----
  function fixRuleOverridesMetrics(){
    try{
      // locate editor panel text
      const editor = Array.from(document.querySelectorAll('pre,code,textarea,div'))
        .find(el => (el.textContent||'').includes('overrides:') && (el.textContent||'').includes('- id:'));
      if(!editor) return;

      const txt = (editor.value || editor.textContent || '');
      const ids = Array.from(txt.matchAll(/\n\s*-\s*id:\s*([A-Z0-9_]+)/g)).map(m=>m[1]);
      const tools = Array.from(txt.matchAll(/\n\s*tool:\s*([a-z0-9_-]+)/ig)).map(m=>m[1]);
      const sevs = Array.from(txt.matchAll(/\n\s*severity:\s*([A-Z]+)/g)).map(m=>m[1]);
      const scopes = Array.from(txt.matchAll(/\n\s*scope:\s*("?[^"\n]*"?)/g)).map(m=>m[1].replace(/"/g,''));

      const n = ids.length || 0;
      if(!n) return;

      // update metrics line if exists
      const metricsNode = Array.from(document.querySelectorAll('*'))
        .find(el => el.children.length===0 && /^Metrics:/i.test((el.textContent||'').trim()));
      if(metricsNode){
        metricsNode.textContent = `Metrics: ${n} overrides active (auto-synced from editor).`;
      }

      // sync table rows (best effort)
      const table = Array.from(document.querySelectorAll('table')).find(t => /Rule Override Table/i.test(t.parentElement ? (t.parentElement.textContent||'') : ''));
      if(table){
        const tbody = table.querySelector('tbody') || table;
        const existingRows = tbody.querySelectorAll('tr').length;
        if(existingRows < n){
          // append missing rows
          for(let i=existingRows;i<n;i++){
            const tr = document.createElement('tr');
            const id = ids[i] || '';
            const tool = tools[i] || '';
            const sev = sevs[i] || '';
            const scope = scopes[i] || '';
            tr.innerHTML = `
              <td>${id}</td>
              <td>${tool}</td>
              <td>-</td>
              <td>${sev}</td>
              <td>${scope}</td>
              <td></td>
            `;
            tbody.appendChild(tr);
          }
        }
      }

      logOnce(MARK+':ovr', 'rule overrides metrics/table synced', {overrides:n});
    }catch(e){
      warnOnce(MARK+':ovrerr','rule overrides patch error', e);
    }
  }

  // ---- bootstrap on route changes / tab changes ----
  function runAll(){
    patchFetchLimit();
    navDedupe();
    addShowingBadges();
    fixDonutTotal();
    fixRuleOverridesMetrics();
  }

  // initial + after a bit (DOM late)
  if(document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', ()=>{ runAll(); setTimeout(runAll, 800); setTimeout(runAll, 1800); });
  }else{
    runAll(); setTimeout(runAll, 800); setTimeout(runAll, 1800);
  }

  // re-run when user navigates between tabs (mutation)
  try{
    const mo = new MutationObserver(()=>{ runAll(); });
    mo.observe(document.body, {subtree:true, childList:true});
  }catch(_){}

})();
"""

# Append safely (keep final newline)
s2 = s.rstrip() + "\n\n" + patch + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended:", MARK, "len=", len(patch))
PY

if [ "$HAVE_NODE" = "1" ]; then
  node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check OK" || { echo "[ERR] node --check failed"; exit 3; }
else
  echo "[WARN] node not found; skipped node --check"
fi

# restart (best effort)
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-units --type=service --all 2>/dev/null | grep -q "vsp-ui-8910.service"; then
    sudo systemctl restart vsp-ui-8910.service
    echo "[OK] restarted: vsp-ui-8910.service"
  else
    echo "[INFO] no systemd service vsp-ui-8910.service found; skip restart"
  fi
else
  echo "[INFO] systemctl not found; skip restart"
fi

echo
echo "== QUICK VERIFY =="
echo "1) Ctrl+F5 /vsp5"
echo "2) Dashboard: donut center should show 'sample / total'"
echo "3) Runs: should show >1 row (default limit=50) + 'Showing X of 298'"
echo "4) Rule Overrides: Metrics should say '${MARK}' synced count (not hardcoded 12/237)"
