#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p0_runsreports_${TS}"
echo "[BACKUP] ${F}.bak_p0_runsreports_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP5_RUNS_REPORTS_COMMERCIAL_P0_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

# Force a commercial renderer shim at top-level (safe IIFE)
inject = r"""
/* %s */
(function(){
  'use strict';
  if (window.__VSP5_RUNS_REPORTS_P0_V1) return;
  window.__VSP5_RUNS_REPORTS_P0_V1 = true;

  function el(tag, cls, txt){
    const x=document.createElement(tag);
    if(cls) x.className=cls;
    if(txt!=null) x.textContent=txt;
    return x;
  }
  function esc(s){ return String(s==null?'':s).replace(/[&<>"']/g, m=>({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[m])); }
  function q(sel, root){ return (root||document).querySelector(sel); }
  function qa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }

  function mkPill(label, ok, tip){
    const a=el('span', 'vsp-pill '+(ok?'ok':'miss'), label);
    if(tip) a.title=tip;
    return a;
  }
  function mkBtn(label, href, enabled, tip){
    const a=el('a', 'vsp-btn '+(enabled?'':'disabled'), label);
    if(enabled){
      a.href=href;
      a.target='_blank';
      a.rel='noopener';
    } else {
      a.href='javascript:void(0)';
      a.onclick=(e)=>{ e.preventDefault(); };
    }
    if(tip) a.title=tip;
    return a;
  }

  function runFileLink(runId, relPath){
    // legacy compat is already wired to run_file2 in your backend; keep it stable for demo
    const u=new URL('/api/vsp/run_file', window.location.origin);
    u.searchParams.set('run_id', runId);
    u.searchParams.set('path', relPath);
    return u.toString();
  }

  function ensureRunsToolbar(host){
    if(q('.vsp-runs-toolbar', host)) return;
    const tb=el('div','vsp-runs-toolbar');
    const left=el('div','left');
    const right=el('div','right');

    const inp=el('input','vsp-inp');
    inp.placeholder='Filter run_id… (gõ để lọc)';
    inp.id='vspRunsFilterQ';

    function mkToggle(id, label){
      const w=el('label','vsp-tog');
      const c=el('input'); c.type='checkbox'; c.id=id;
      const t=el('span','',label);
      w.appendChild(c); w.appendChild(t);
      return w;
    }
    const tHtml=mkToggle('vspHasHtml','has HTML');
    const tJson=mkToggle('vspHasJson','has JSON');
    const tSum=mkToggle('vspHasSum','has SUM');

    right.appendChild(inp);
    right.appendChild(tHtml);
    right.appendChild(tJson);
    right.appendChild(tSum);

    tb.appendChild(left);
    tb.appendChild(right);
    host.prepend(tb);
  }

  function applyFilter(rows){
    const qv=(q('#vspRunsFilterQ')?.value||'').trim().toLowerCase();
    const fHtml=!!q('#vspHasHtml')?.checked;
    const fJson=!!q('#vspHasJson')?.checked;
    const fSum=!!q('#vspHasSum')?.checked;

    rows.forEach(r=>{
      const id=(r.getAttribute('data-run-id')||'').toLowerCase();
      const hasHtml=r.getAttribute('data-has-html')==='1';
      const hasJson=r.getAttribute('data-has-json')==='1';
      const hasSum=r.getAttribute('data-has-sum')==='1';

      let ok=true;
      if(qv && !id.includes(qv)) ok=false;
      if(fHtml && !hasHtml) ok=false;
      if(fJson && !hasJson) ok=false;
      if(fSum && !hasSum) ok=false;

      r.style.display = ok ? '' : 'none';
    });
  }

  function injectStylesOnce(){
    if(document.getElementById('vspRunsP0Styles')) return;
    const css = `
      .vsp-runs-toolbar{display:flex;justify-content:space-between;align-items:center;margin:10px 0 12px 0;gap:10px}
      .vsp-runs-toolbar .right{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
      .vsp-inp{background:#0e1420;border:1px solid rgba(255,255,255,.12);color:#e7eefc;border-radius:10px;padding:8px 10px;min-width:260px}
      .vsp-tog{display:inline-flex;align-items:center;gap:6px;font-size:12px;color:#cfe1ff;opacity:.9}
      .vsp-tog input{transform:scale(1.05)}
      .vsp-pill{display:inline-block;font-size:11px;border-radius:999px;padding:3px 8px;margin-right:6px;border:1px solid rgba(255,255,255,.12)}
      .vsp-pill.ok{background:rgba(60,220,140,.12);color:#bfffe0}
      .vsp-pill.miss{background:rgba(255,110,110,.10);color:#ffd0d0;opacity:.85}
      .vsp-btn{display:inline-block;font-size:12px;border-radius:10px;padding:6px 10px;margin-right:6px;border:1px solid rgba(255,255,255,.14);color:#dbe9ff;text-decoration:none}
      .vsp-btn:hover{filter:brightness(1.08)}
      .vsp-btn.disabled{opacity:.35;pointer-events:none}
      .vsp-reports-cell{white-space:nowrap}
    `;
    const st=document.createElement('style');
    st.id='vspRunsP0Styles';
    st.textContent=css;
    document.head.appendChild(st);
  }

  function enhanceRunsTable(){
    injectStylesOnce();

    // Works with common containers. If your tab uses different id, it still tries table detection.
    const host = q('#tab-runs') || q('#runs') || q('[data-tab="runs"]') || document.body;
    ensureRunsToolbar(host);

    const table = q('table', host) || q('table');
    if(!table) return;

    // Identify rows: skip header
    const trs = qa('tbody tr', table);
    if(!trs.length) return;

    trs.forEach(tr=>{
      // We expect run_id cell is first/has link; try best-effort parse
      const tds=qa('td', tr);
      if(!tds.length) return;
      const runId = (tds[0].innerText||'').trim();
      if(!runId) return;

      // Find "has" encoded in DOM if exists, else attempt from text badges
      // Default: unknown => false (so filters won't hide unless toggled)
      let hasHtml=false, hasJson=false, hasSum=false;

      // Heuristic: if backend already wrote pills text somewhere
      const txt = tr.innerText.toLowerCase();
      if(txt.includes('html:true') || txt.includes('has html')) hasHtml=true;
      if(txt.includes('json:true') || txt.includes('has json')) hasJson=true;
      if(txt.includes('summary:true') || txt.includes('sum:true') || txt.includes('has sum')) hasSum=true;

      tr.setAttribute('data-run-id', runId);
      tr.setAttribute('data-has-html', hasHtml?'1':'0');
      tr.setAttribute('data-has-json', hasJson?'1':'0');
      tr.setAttribute('data-has-sum', hasSum?'1':'0');

      // Ensure REPORTS cell exists: last column assumed
      const reportsTd = tds[tds.length-1];
      reportsTd.classList.add('vsp-reports-cell');

      // Compose “commercial strip”
      reportsTd.innerHTML = '';
      const pills=el('div','vsp-pills');
      pills.appendChild(mkPill('HTML', hasHtml, hasHtml?'HTML report available':'missing reports/index.html'));
      pills.appendChild(mkPill('JSON', hasJson, hasJson?'findings_unified.json available':'missing findings_unified.json'));
      pills.appendChild(mkPill('SUM',  hasSum,  hasSum ?'run summary available':'missing reports/run_gate_summary.json or SUMMARY.txt'));
      reportsTd.appendChild(pills);

      const btns=el('div','vsp-btns');
      btns.appendChild(mkBtn('Open HTML', runFileLink(runId,'reports/index.html'), hasHtml, 'Open reports/index.html'));
      btns.appendChild(mkBtn('Open JSON', runFileLink(runId,'findings_unified.json'), hasJson, 'Open findings_unified.json'));
      // SUM: prefer run_gate_summary.json; if missing, fallback to SUMMARY.txt
      btns.appendChild(mkBtn('Open SUM',  runFileLink(runId,'reports/run_gate_summary.json'), hasSum, 'Open reports/run_gate_summary.json (or SUMMARY.txt)'));
      btns.appendChild(mkBtn('Open TXT',  runFileLink(runId,'SUMMARY.txt'), true, 'Open SUMMARY.txt'));
      reportsTd.appendChild(btns);
    });

    // bind filters
    const rows = qa('tbody tr', table);
    ['vspRunsFilterQ','vspHasHtml','vspHasJson','vspHasSum'].forEach(id=>{
      const x=q('#'+id);
      if(!x) return;
      x.addEventListener('input', ()=>applyFilter(rows));
      x.addEventListener('change', ()=>applyFilter(rows));
    });
    applyFilter(rows);
  }

  // Run once now + keepalive re-apply (covers rerender)
  function tick(){
    try{ enhanceRunsTable(); }catch(e){}
  }
  tick();
  setInterval(tick, 2500);
})();
""" % MARK

# Put inject at beginning to guarantee it executes
s2 = inject + "\n\n" + s
p.write_text(s2, encoding="utf-8")
print("[OK] injected:", MARK)
PY

if command -v node >/dev/null 2>&1; then
  node --check static/js/vsp_runs_tab_resolved_v1.js && echo "[OK] node --check OK"
else
  echo "[SKIP] node missing"
fi

echo "[NEXT] restart UI service: systemctl restart vsp-ui-8910.service (or your restart script)"
