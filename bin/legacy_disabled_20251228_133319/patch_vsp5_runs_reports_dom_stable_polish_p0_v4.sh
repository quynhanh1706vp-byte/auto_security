#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_dom_polish_${TS}"
echo "[BACKUP] ${F}.bak_dom_polish_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP5_RUNS_REPORTS_DOM_STABLE_POLISH_P0_V4"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject = r"""
/* === VSP5_RUNS_REPORTS_DOM_STABLE_POLISH_P0_V4 === */
(function(){
  'use strict';
  if (window.__VSP5_RUNS_REPORTS_DOM_STABLE_POLISH_P0_V4) return;
  window.__VSP5_RUNS_REPORTS_DOM_STABLE_POLISH_P0_V4 = true;

  function ensureStyle(){
    if (document.getElementById('vsp5-runs-polish-css')) return;
    const css = `
      :root{
        --vsp5-fg: rgba(255,255,255,.86);
        --vsp5-fg2: rgba(255,255,255,.72);
        --vsp5-border: rgba(255,255,255,.10);
        --vsp5-card: rgba(255,255,255,.04);
        --vsp5-card2: rgba(0,0,0,.20);
      }
      .vsp5-action-strip{ display:flex; gap:8px; flex-wrap:wrap; align-items:center; }
      .vsp5-action-strip a, .vsp5-action-strip button{
        font-size:12px; line-height:1;
        padding:6px 10px; border-radius:10px;
        border:1px solid var(--vsp5-border);
        background: linear-gradient(180deg,var(--vsp5-card),var(--vsp5-card2));
        color: var(--vsp5-fg2);
        text-decoration:none;
        cursor:pointer;
      }
      .vsp5-action-strip a:hover, .vsp5-action-strip button:hover{
        color: var(--vsp5-fg);
        border-color: rgba(255,255,255,.18);
      }
      .vsp5-pill{ display:inline-flex; align-items:center; justify-content:center;
        min-width:20px; height:18px; padding:0 6px; border-radius:999px;
        border:1px solid var(--vsp5-border);
        color: var(--vsp5-fg2);
        font-size:11px;
        background: rgba(255,255,255,.03);
      }
      .vsp5-pill.ok{ color: rgba(180,255,210,.92); border-color: rgba(180,255,210,.22); background: rgba(180,255,210,.06); }
      .vsp5-pill.no{ color: rgba(255,220,180,.86); border-color: rgba(255,220,180,.18); background: rgba(255,220,180,.05); }
      .vsp5-muted{ color: var(--vsp5-fg2); }
    `;
    const st = document.createElement('style');
    st.id = 'vsp5-runs-polish-css';
    st.textContent = css;
    document.head.appendChild(st);
  }

  function isReportsCell(td){
    // Heuristic: cell has >=2 links/buttons and at least 1 href contains run_file or "/reports/"
    const links = td.querySelectorAll('a[href],button');
    if (links.length < 2) return false;
    for (const a of td.querySelectorAll('a[href]')) {
      const h = (a.getAttribute('href')||'');
      if (h.includes('/api/vsp/run_file') || h.includes('/reports/') || h.includes('run_file?')) return true;
    }
    return false;
  }

  function classifyAction(el){
    const t = (el.textContent||'').trim().toUpperCase();
    if (t === 'H' || t.includes('HTML')) return 'HTML';
    if (t === 'J' || t.includes('JSON')) return 'JSON';
    if (t === 'S' || t.includes('SUM')) return 'SUM';
    if (t === 'T' || t.includes('TXT')) return 'TXT';
    return '';
  }

  function enhanceOnce(){
    ensureStyle();
    const tb = document.getElementById('tb') || document.querySelector('table#tb') || document.querySelector('table');
    if (!tb) return;

    const tbody = tb.tBodies && tb.tBodies[0] ? tb.tBodies[0] : tb;
    const rows = tbody.querySelectorAll('tr');
    for (const tr of rows){
      const tds = tr.querySelectorAll('td');
      for (const td of tds){
        if (!isReportsCell(td)) continue;

        // Wrap actions into a strip (idempotent)
        if (!td.classList.contains('vsp5-reports-cell')){
          td.classList.add('vsp5-reports-cell');
        }

        // Find a container to style; if already wrapped, skip re-wrap
        let strip = td.querySelector(':scope > .vsp5-action-strip');
        if (!strip){
          // move all direct children into strip to avoid renderer fragments
          strip = document.createElement('div');
          strip.className = 'vsp5-action-strip';

          const nodes = Array.from(td.childNodes);
          td.textContent = '';
          td.appendChild(strip);
          for (const n of nodes){
            if (n.nodeType === 3 && !n.textContent.trim()) continue;
            strip.appendChild(n);
          }
        }

        // Add pills for has flags if present as H/J/S characters or spans
        // Also normalize action tags
        const acts = strip.querySelectorAll('a,button');
        for (const a of acts){
          const k = classifyAction(a);
          if (k) a.setAttribute('data-vsp5-act', k);
        }

        // If there are standalone "H/J/S" markers, turn them into pills
        const text = strip.textContent || '';
        // Only do pill injection once per row
        if (!strip.querySelector('.vsp5-pill')){
          const pillWrap = document.createElement('div');
          pillWrap.style.display='flex';
          pillWrap.style.gap='6px';
          pillWrap.style.alignItems='center';

          const mk = (label, ok) => {
            const sp=document.createElement('span');
            sp.className='vsp5-pill ' + (ok?'ok':'no');
            sp.textContent=label;
            return sp;
          };

          // Determine ok by existing presence of action link types
          const has = new Set(Array.from(strip.querySelectorAll('[data-vsp5-act]')).map(x=>x.getAttribute('data-vsp5-act')));
          pillWrap.appendChild(mk('H', has.has('HTML')));
          pillWrap.appendChild(mk('J', has.has('JSON')));
          pillWrap.appendChild(mk('S', has.has('SUM')));
          // Insert pills at end
          strip.appendChild(pillWrap);
        }
      }
    }
  }

  // Stable repaint: observe table body changes & re-enhance
  function start(){
    enhanceOnce();
    const tb = document.getElementById('tb') || document.querySelector('table#tb') || document.querySelector('table');
    if (!tb) return;

    const tbody = tb.tBodies && tb.tBodies[0] ? tb.tBodies[0] : tb;
    if (tbody.__vsp5Obs) return;

    let raf = 0;
    const obs = new MutationObserver(() => {
      if (raf) return;
      raf = requestAnimationFrame(() => { raf = 0; enhanceOnce(); });
    });
    obs.observe(tbody, { childList:true, subtree:true });
    tbody.__vsp5Obs = obs;
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, {once:true});
  } else {
    start();
  }
})();
"""

# Append at end (safe even if upstream changes)
s2 = s + "\n\n" + inject + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] injected:", MARK)
PY

node --check static/js/vsp_runs_tab_resolved_v1.js >/dev/null 2>&1 && echo "[OK] node --check OK" || { echo "[ERR] node --check failed"; exit 3; }

echo "[NEXT] restart UI then Ctrl+F5 /vsp5"
