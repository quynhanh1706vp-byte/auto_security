#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_UI_COMMERCIAL_UX_P1_V1"

JS="static/js/vsp_ui_commercial_ux_p1_v1.js"
mkdir -p static/js
[ -f "$JS" ] && cp -f "$JS" "$JS.bak_${TS}" && echo "[BACKUP] $JS.bak_${TS}"

cat > "$JS" <<'JS'
/* VSP_UI_COMMERCIAL_UX_P1_V1
 * - Make dashboard/runs feel commercial: pills, hover, click-to-select RID, gentle auto refresh
 */
(function(){
  'use strict';
  if (window.__VSP_UI_COMMERCIAL_UX_P1_V1) return;
  window.__VSP_UI_COMMERCIAL_UX_P1_V1 = 1;

  // ---------- helpers ----------
  const qs = (s, r=document)=>r.querySelector(s);
  const qsa = (s, r=document)=>Array.from(r.querySelectorAll(s));
  const on = (el, ev, fn)=>el && el.addEventListener(ev, fn, {passive:true});

  function pill(text, kind){
    const span = document.createElement('span');
    span.className = 'vsp-pill ' + (kind ? ('vsp-pill-' + kind) : 'vsp-pill-muted');
    span.textContent = text;
    return span;
  }

  function normalizeVerdict(v){
    v = (v||'').toString().toUpperCase();
    if (v.includes('DEGRA')) return 'DEGRADED';
    if (v.includes('RED') || v.includes('FAIL') || v.includes('BLOCK')) return 'RED';
    if (v.includes('AMBER') || v.includes('WARN') || v.includes('YELLOW')) return 'AMBER';
    if (v.includes('GREEN') || v.includes('PASS') || v.includes('OK')) return 'GREEN';
    return v || 'N/A';
  }

  function verdictKind(v){
    v = normalizeVerdict(v);
    if (v === 'GREEN') return 'green';
    if (v === 'AMBER') return 'amber';
    if (v === 'RED') return 'red';
    if (v === 'DEGRADED') return 'degraded';
    return 'muted';
  }

  function ensureCss(){
    if (qs('#vsp-ui-commercial-ux-css')) return;
    const style = document.createElement('style');
    style.id = 'vsp-ui-commercial-ux-css';
    style.textContent = `
      .vsp-pill{display:inline-flex;align-items:center;gap:.35rem;padding:.18rem .55rem;border-radius:999px;
        font-size:12px;line-height:1;border:1px solid rgba(255,255,255,.10);background:rgba(255,255,255,.06);color:#cbd5e1}
      .vsp-pill-green{background:rgba(16,185,129,.12);border-color:rgba(16,185,129,.25);color:#a7f3d0}
      .vsp-pill-amber{background:rgba(245,158,11,.12);border-color:rgba(245,158,11,.25);color:#fde68a}
      .vsp-pill-red{background:rgba(239,68,68,.10);border-color:rgba(239,68,68,.25);color:#fecaca}
      .vsp-pill-degraded{background:rgba(99,102,241,.10);border-color:rgba(99,102,241,.22);color:#c7d2fe}
      .vsp-pill-muted{opacity:.85}

      .vsp-runs-row{transition:transform .08s ease, background .12s ease}
      .vsp-runs-row:hover{background:rgba(255,255,255,.04);transform:translateY(-1px)}
      .vsp-runs-row.is-active{outline:1px solid rgba(99,102,241,.35);background:rgba(99,102,241,.08)}
      .vsp-kpi-sub{opacity:.75;font-size:12px;margin-top:.25rem}
    `;
    document.head.appendChild(style);
  }

  function setRid(rid){
    try{
      // existing app uses RID in hash or local storage; support both
      localStorage.setItem('vsp_rid', rid);
    }catch(_){}
    // update UI field if exists
    const ridBox = qsa('input,textarea').find(x=> (x.placeholder||'').toLowerCase().includes('rid') || (x.value||'').startsWith('VSP_'));
    if (ridBox && ridBox.value !== rid) ridBox.value = rid;

    // set in sidebar if there is a pill/card
    const ridLabel = qsa('*').find(n=> (n.textContent||'').trim()==='RID');
    if (ridLabel && ridLabel.parentElement){
      const v = ridLabel.parentElement.querySelector('.vsp-kv-value,.value,div,span');
      if (v) v.textContent = rid;
    }
  }

  // ---------- decorate dashboard KPIs ----------
  function decorateDashboard(){
    ensureCss();
    // try to find KPI cards by headings
    const cards = qsa('.vsp-card, .dashboard-card, .card');
    cards.forEach(card=>{
      const h = qs('h3,h2,.title', card);
      if (!h) return;
      const t = (h.textContent||'').trim().toLowerCase();
      if (!t) return;

      // if card already has pills -> skip
      if (card.querySelector('.vsp-pill')) return;

      // infer verdict from text inside
      const raw = (card.textContent||'');
      const v = normalizeVerdict(raw);
      const k = verdictKind(v);

      if (t.includes('overall') || t.includes('gate') || t.includes('tools')){
        const row = document.createElement('div');
        row.style.display='flex';
        row.style.gap='.5rem';
        row.style.marginTop='.45rem';
        row.appendChild(pill(v, k));
        card.appendChild(row);
      }
    });
  }

  // ---------- runs table UX ----------
  function decorateRuns(){
    ensureCss();
    // find likely table rows
    const rows = qsa('tr, .row, .vsp-run-row, .runs-row').filter(r=>{
      const txt = (r.textContent||'').trim();
      return txt.includes('VSP_') && (txt.includes('zip') || txt.includes('pdf') || txt.includes('html') || txt.includes('status'));
    });

    rows.forEach(r=>{
      r.classList.add('vsp-runs-row');
      if (r.__vsp_bound) return;
      r.__vsp_bound = 1;

      // extract run id
      const m = (r.textContent||'').match(/VSP_[A-Za-z0-9_:-]+/);
      const rid = m ? m[0] : '';
      if (!rid) return;

      on(r, 'click', (e)=>{
        // ignore if clicking buttons/links
        const tag = (e.target && e.target.tagName) ? e.target.tagName.toLowerCase() : '';
        if (tag === 'button' || tag === 'a') return;
        // highlight
        qsa('.vsp-runs-row.is-active').forEach(x=>x.classList.remove('is-active'));
        r.classList.add('is-active');
        setRid(rid);
      });

      // add pills into row if there are plain "YES/NO" cells
      if (!r.querySelector('.vsp-pill')){
        const vtxt = (r.textContent||'').toUpperCase();
        const hasFindings = vtxt.includes('YES') ? 'HAS FINDINGS' : (vtxt.includes('NO') ? 'NO FINDINGS' : '');
        const degraded = vtxt.includes('DEGRA') ? 'DEGRADED' : '';
        const pillBox = document.createElement('div');
        pillBox.style.display='inline-flex';
        pillBox.style.gap='.35rem';
        pillBox.style.marginLeft='.5rem';
        if (hasFindings) pillBox.appendChild(pill(hasFindings, hasFindings==='NO FINDINGS'?'amber':'green'));
        if (degraded) pillBox.appendChild(pill(degraded, 'degraded'));
        if (pillBox.childNodes.length) r.appendChild(pillBox);
      }
    });
  }

  // ---------- gentle auto refresh on #runs ----------
  let lastTick = 0;
  function tick(){
    const now = Date.now();
    if (now - lastTick < 30_000) return;
    lastTick = now;
    const h = (location.hash||'').toLowerCase();
    if (!h.includes('runs')) return;
    // click refresh button if exists
    const btn = qsa('button');
    const refresh = qsa('button, a');
    const list = qsa('button, a');
    const b = qsa('button') && qsa('button', document.body);
    const cand = qsa('button, a').find(x=> (x.textContent||'').trim().toLowerCase()==='refresh');
    if (cand) { try{ cand.click(); }catch(_){} }
  }

  // run on load and on route change
  function runAll(){
    const h = (location.hash||'').toLowerCase();
    if (h.includes('dashboard')) decorateDashboard();
    if (h.includes('runs')) decorateRuns();
  }

  window.addEventListener('hashchange', ()=>setTimeout(runAll, 50));
  setInterval(()=>{ try{ tick(); runAll(); }catch(_){ } }, 2000);
  setTimeout(runAll, 80);
})();
JS

node --check "$JS" >/dev/null && echo "[OK] node --check $JS"

# inject into template head (so it runs everywhere)
TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }
cp -f "$TPL" "$TPL.bak_${MARK}_${TS}" && echo "[BACKUP] $TPL.bak_${MARK}_${TS}"

python3 - "$TPL" "$JS" "$MARK" "$TS" <<'PY'
from pathlib import Path
import re, sys
tpl = Path(sys.argv[1]); js = sys.argv[2]; mark=sys.argv[3]; ts=sys.argv[4]
s = tpl.read_text(encoding="utf-8", errors="replace")
if mark in s:
    print("[OK] already injected"); raise SystemExit(0)
tag = f'\n<!-- {mark} -->\n<script src="/{js}?v={ts}"></script>\n'
if re.search(r'</head\s*>', s, flags=re.I):
    s2 = re.sub(r'(</head\s*>)', tag + r'\1', s, count=1, flags=re.I)
else:
    s2 = tag + s
tpl.write_text(s2, encoding="utf-8")
print("[OK] injected:", tpl)
PY

echo "DONE. Ctrl+Shift+R rồi test #runs click row -> RID update."
