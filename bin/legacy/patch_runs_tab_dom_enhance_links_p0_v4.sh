#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_domlinks_${TS}"
echo "[BACKUP] ${JS}.bak_domlinks_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_runs_tab_resolved_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# Replace previous V3 block if present (it was appended at end)
pat = r"// VSP_RUNS_DOM_ENHANCE_OPEN_HTML_P0_V3[\s\S]*\Z"
MARK = "VSP_RUNS_DOM_ENHANCE_LINKS_P0_V4"

addon = r"""
// VSP_RUNS_DOM_ENHANCE_LINKS_P0_V4
(function(){
  'use strict';

  function _ridFromRowText(t){
    try{
      const m = String(t||'').match(/[A-Za-z0-9_.:-]{6,128}/g);
      if (!m) return '';
      for (const x of m){ if (x.includes('RUN')) return x; }
      return m[0] || '';
    }catch(e){ return ''; }
  }

  async function _fetchRuns(){
    const r = await fetch('/api/vsp/runs?limit=500', {headers:{'accept':'application/json'}});
    if (!r.ok) throw new Error('runs api not ok: '+r.status);
    const ct = r.headers.get('content-type')||'';
    if (!ct.includes('application/json')) throw new Error('runs api not json: '+ct);
    return await r.json();
  }

  function _mkBtn(text, url){
    const a=document.createElement('a');
    a.href=url;
    a.target='_blank';
    a.rel='noopener';
    a.className='btn btn-sm';
    a.textContent=text;
    return a;
  }

  function _injectLinks(map){
    const tbl = document.querySelector('table');
    if (!tbl) return false;
    const rows = tbl.querySelectorAll('tbody tr');
    if (!rows || !rows.length) return false;

    rows.forEach(tr=>{
      try{
        if (tr.dataset.vspLinks === '1') return;
        const rid = _ridFromRowText(tr.innerText);
        if (!rid) return;

        const links = map.get(rid);
        if (!links) return;

        const tds = tr.querySelectorAll('td');
        const td = tds.length ? tds[tds.length-1] : tr;

        if (td.querySelector('a.vsp-open-any')) { tr.dataset.vspLinks='1'; return; }

        const wrap = document.createElement('span');
        wrap.className = 'vsp-open-any';

        // order: HTML, JSON, Summary, CSV, SARIF
        const order = [
          ['Open HTML','html'],
          ['Open JSON','json'],
          ['Open Summary','summary'],
          ['Open CSV','csv'],
          ['Open SARIF','sarif'],
        ];

        let added = 0;
        for (const [label,key] of order){
          const url = links[key];
          if (url){
            if (added>0) wrap.appendChild(document.createTextNode(' '));
            const btn=_mkBtn(label, url);
            btn.classList.add('vsp-open-any');
            wrap.appendChild(btn);
            added++;
          }
        }
        if (added){
          td.appendChild(document.createTextNode(' '));
          td.appendChild(wrap);
          tr.dataset.vspLinks='1';
        }
      }catch(e){}
    });
    return true;
  }

  async function _run(){
    try{
      const data = await _fetchRuns();
      const items = Array.isArray(data.items)? data.items : [];
      const map = new Map();

      for (const it of items){
        const rid = String(it.run_id || it.rid || it.id || '');
        if (!rid) continue;
        const has = (it.has && typeof it.has==='object')? it.has : {};

        const links = {};
        const hp = (typeof has.html_path === 'string') ? has.html_path : '';
        if (hp && hp.startsWith('/api/vsp/run_file')) links.html = hp;

        const jp = (typeof has.json_path === 'string') ? has.json_path : '';
        if (jp && jp.startsWith('/api/vsp/run_file')) links.json = jp;

        const sp = (typeof has.summary_path === 'string') ? has.summary_path : '';
        if (sp && sp.startsWith('/api/vsp/run_file')) links.summary = sp;

        const cp = (typeof has.csv_path === 'string') ? has.csv_path : '';
        if (cp && cp.startsWith('/api/vsp/run_file')) links.csv = cp;

        const sap = (typeof has.sarif_path === 'string') ? has.sarif_path : '';
        if (sap && sap.startsWith('/api/vsp/run_file')) links.sarif = sap;

        // if API only marks boolean (rare), still build default urls
        if (!links.html && (has.html===true || has.html===1 || has.html==="true")){
          links.html = '/api/vsp/run_file?rid='+encodeURIComponent(rid)+'&name='+encodeURIComponent('reports/index.html');
        }
        if (!links.json && (has.json===true || has.json===1 || has.json==="true")){
          links.json = '/api/vsp/run_file?rid='+encodeURIComponent(rid)+'&name='+encodeURIComponent('reports/findings_unified.json');
        }
        if (!links.summary && (has.summary===true || has.summary===1 || has.summary==="true")){
          links.summary = '/api/vsp/run_file?rid='+encodeURIComponent(rid)+'&name='+encodeURIComponent('reports/run_gate_summary.json');
        }
        if (!links.csv && (has.csv===true || has.csv===1 || has.csv==="true")){
          links.csv = '/api/vsp/run_file?rid='+encodeURIComponent(rid)+'&name='+encodeURIComponent('reports/findings_unified.csv');
        }
        if (!links.sarif && (has.sarif===true || has.sarif===1 || has.sarif==="true")){
          links.sarif = '/api/vsp/run_file?rid='+encodeURIComponent(rid)+'&name='+encodeURIComponent('reports/findings_unified.sarif');
        }

        if (Object.keys(links).length) map.set(rid, links);
      }

      // retry to catch table render timing
      for (let i=0;i<30;i++){
        const ok = _injectLinks(map);
        if (ok) break;
        await new Promise(res=>setTimeout(res,200));
      }
    }catch(e){
      try{ console.warn('[VSP] DOM enhance links failed:', e); }catch(_){}
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', _run);
  else _run();
})();
"""

if re.search(pat, s):
    s2 = re.sub(pat, addon+"\n", s, count=1)
    print("[OK] replaced previous V3 block with V4")
else:
    # append at end
    s2 = s.rstrip() + "\n\n" + addon + "\n"
    print("[OK] appended V4 block (V3 not found)")

if MARK not in s2:
    raise SystemExit("[ERR] marker missing after patch")

p.write_text(s2, encoding="utf-8")
print("[OK] wrote:", p)
PY

node --check "$JS"
echo "[OK] node --check OK"

sudo systemctl restart vsp-ui-8910.service
sleep 0.8

echo "== smoke /runs =="
curl -sS -I http://127.0.0.1:8910/runs | sed -n '1,15p'
