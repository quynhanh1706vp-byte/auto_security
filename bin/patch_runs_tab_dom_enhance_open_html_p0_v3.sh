#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_domopenhtml_${TS}"
echo "[BACKUP] ${JS}.bak_domopenhtml_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_RUNS_DOM_ENHANCE_OPEN_HTML_P0_V3"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

addon = r"""
// VSP_RUNS_DOM_ENHANCE_OPEN_HTML_P0_V3
(function(){
  'use strict';

  function _ridFromRowText(t){
    try{
      // pick first token that looks like RUN_ID-ish
      const m = String(t||'').match(/[A-Za-z0-9_.:-]{6,128}/g);
      if (!m) return '';
      // prefer ones containing "RUN" (common)
      for (const x of m){ if (x.includes('RUN')) return x; }
      return m[0] || '';
    }catch(e){ return ''; }
  }

  async function _fetchRuns(){
    const r = await fetch('/api/vsp/runs?limit=200', {headers:{'accept':'application/json'}});
    if (!r.ok) throw new Error('runs api not ok: '+r.status);
    const ct = r.headers.get('content-type')||'';
    if (!ct.includes('application/json')) throw new Error('runs api not json: '+ct);
    return await r.json();
  }

  function _injectLinks(map){
    const tbl = document.querySelector('table');
    if (!tbl) return false;
    const rows = tbl.querySelectorAll('tbody tr');
    if (!rows || !rows.length) return false;

    rows.forEach(tr=>{
      try{
        if (tr.dataset.vspOpenHtml === '1') return;
        const rid = _ridFromRowText(tr.innerText);
        if (!rid) return;

        const url = map.get(rid);
        if (!url) return;

        // choose last cell as actions
        const tds = tr.querySelectorAll('td');
        const td = tds.length ? tds[tds.length-1] : tr;
        // avoid duplicates
        if (td.querySelector('a.vsp-open-html')) { tr.dataset.vspOpenHtml='1'; return; }

        const a=document.createElement('a');
        a.href=url;
        a.target='_blank';
        a.rel='noopener';
        a.className='btn btn-sm vsp-open-html';
        a.textContent='Open HTML';
        td.appendChild(document.createTextNode(' '));
        td.appendChild(a);
        tr.dataset.vspOpenHtml='1';
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
        const has = (it.has && typeof it.has==='object')? it.has : {};
        const hp = (typeof has.html_path === 'string') ? has.html_path : '';
        if (rid && hp && hp.startsWith('/api/vsp/run_file')) map.set(rid, hp);
        else if (rid && (has.html===true || has.html===1 || has.html==="true")){
          map.set(rid, '/api/vsp/run_file?rid='+encodeURIComponent(rid)+'&name='+encodeURIComponent('reports/index.html'));
        }
      }
      // keep trying a bit to catch table render timing
      let ok=false;
      for (let i=0;i<30;i++){
        ok = _injectLinks(map);
        if (ok) break;
        await new Promise(res=>setTimeout(res,200));
      }
    }catch(e){
      // console-only; avoid breaking UI
      try{ console.warn('[VSP] DOM enhance Open HTML failed:', e); }catch(_){}
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', _run);
  else _run();
})();
"""

s2 = s.rstrip() + "\n\n" + addon + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended DOM enhancer:", MARK)
PY

node --check "$JS"
echo "[OK] node --check OK"

sudo systemctl restart vsp-ui-8910.service
sleep 0.8

echo "== smoke /runs =="
curl -sS -I http://127.0.0.1:8910/runs | sed -n '1,15p'
