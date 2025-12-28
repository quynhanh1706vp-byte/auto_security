#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p466a3_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F" "$OUT/$(basename "$F").bak_${TS}"
echo "[OK] backup => $OUT/$(basename "$F").bak_${TS}" | tee -a "$OUT/log.txt"

python3 - "$F" <<'PY'
import sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P466A3_RUNS_DEDUPE_ANYROW_V1"
if MARK in s:
    print("[OK] already patched P466a3")
    raise SystemExit(0)

addon = r'''
/* --- VSP_P466A3_RUNS_DEDUPE_ANYROW_V1 --- */
(function(){
  if (window.__VSP_P466A3_ON) return;
  window.__VSP_P466A3_ON = true;

  const LS_SORT="vsp_runs_sort_v2";
  const LS_SEL ="vsp_runs_selected_rid_v2";

  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }
  function t(el){ return (el && el.textContent ? el.textContent : "").trim(); }

  function ensureCss(){
    if (qs('#vsp_p466a3_css')) return;
    const st=document.createElement('style');
    st.id='vsp_p466a3_css';
    st.textContent = `
      .vsp-p466a3-hidden{ display:none !important; }
      .vsp-p466a3-selected{ outline:2px solid rgba(255,255,255,.14); background: rgba(255,255,255,.04)!important; border-radius:12px; }
      .vsp-p466a3-sort{ margin-left:10px; padding:8px 10px; border-radius:10px;
        border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); color:#fff; }
    `;
    document.head.appendChild(st);
  }

  function getSort(){ try{return localStorage.getItem(LS_SORT)||"new";}catch(e){return "new";} }
  function setSort(v){ try{localStorage.setItem(LS_SORT,v);}catch(e){} }
  function getSel(){ try{return (localStorage.getItem(LS_SEL)||"").trim();}catch(e){return "";} }
  function setSel(rid){ try{localStorage.setItem(LS_SEL,String(rid||"").trim());}catch(e){} }

  function findRunsSection(){
    // best effort: section containing Filter input + Use RID buttons
    const btn = qsa('button').find(b => t(b).toLowerCase()==='use rid');
    const inp = qsa('input').find(i => (i.getAttribute('placeholder')||'').toLowerCase().includes('filter by'));
    return (inp && (inp.closest('section')||inp.closest('.card')||inp.closest('div')))
        || (btn && (btn.closest('section')||btn.closest('.card')||btn.closest('div')))
        || document.body;
  }

  function findFilterInput(root){
    return qsa('input', root).find(i => (i.getAttribute('placeholder')||'').toLowerCase().includes('filter by')) || null;
  }

  function ensureSortSelect(root){
    ensureCss();
    const inp = findFilterInput(root);
    if(!inp) return;
    // avoid double insert
    if (inp.parentElement && qs('select.vsp-p466a3-sort', inp.parentElement)) return;

    const sel=document.createElement('select');
    sel.className='vsp-p466a3-sort';
    sel.innerHTML = `
      <option value="new">Sort: Newest</option>
      <option value="old">Sort: Oldest</option>
      <option value="none">Sort: None</option>
    `;
    sel.value = getSort();
    sel.addEventListener('change', ()=>{ setSort(sel.value); apply(root); });
    inp.insertAdjacentElement('afterend', sel);
  }

  function rowFromUseRidButton(btn){
    // climb a few levels to find a “row container” (works for div-based list)
    let n = btn;
    for(let i=0;i<6 && n;i++){
      if (n.tagName && (n.tagName.toLowerCase()==='tr')) return n;
      // heuristics: a row usually contains "Reports.tgz" or "Dashboard" + "CSV"
      const txt = t(n).toLowerCase();
      if (txt.includes('reports.tgz') && txt.includes('dashboard') && txt.includes('csv')) return n;
      n = n.parentElement;
    }
    return btn.closest('tr') || btn.closest('div') || null;
  }

  function extractRidFromText(text){
    const m1 = text.match(/\bVSP_[A-Z0-9_]+\b/);
    if (m1) return m1[0];
    const m2 = text.match(/\bp\d+[a-z0-9_]+\b/i);
    if (m2) return m2[0];
    return "";
  }

  function extractTs(text){
    const m = text.match(/(20\d{2})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})/);
    if(!m) return 0;
    const y=+m[1], mo=+m[2], d=+m[3], hh=+m[4], mm=+m[5];
    const dt=new Date(y, mo-1, d, hh, mm, 0, 0);
    return dt.getTime()||0;
  }

  function collectRows(root){
    const buttons = qsa('button', root).filter(b => t(b).toLowerCase()==='use rid');
    const rows = [];
    for(const b of buttons){
      const row = rowFromUseRidButton(b);
      if(!row) continue;
      // avoid duplicates in the rows list itself
      if(rows.indexOf(row)===-1) rows.push(row);
    }
    return rows;
  }

  function patchRunsLoaded(root, n){
    // Update any element showing "Runs loaded: undefined" within root
    const all = qsa('*', root);
    for(const el of all){
      if(el.children && el.children.length) continue;
      const tt = t(el);
      if(!tt) continue;
      if(tt.includes('Runs loaded:') && tt.includes('undefined')){
        el.textContent = 'Runs loaded: ' + String(n);
        return;
      }
    }
  }

  function dedupe(root, rows){
    const seen = new Set();
    let unique = 0;
    for(const r of rows){
      const txt = t(r);
      const rid = extractRidFromText(txt);
      const ts  = extractTs(txt);
      const key = (rid||'') + '|' + String(ts||0);
      if(!rid){
        r.classList.remove('vsp-p466a3-hidden');
        continue;
      }
      if(seen.has(key)){
        r.classList.add('vsp-p466a3-hidden');
      }else{
        seen.add(key);
        r.classList.remove('vsp-p466a3-hidden');
        unique += 1;
      }
    }
    patchRunsLoaded(root, unique);
    return unique;
  }

  function sortRows(root, rows){
    const mode = getSort();
    if(mode === 'none') return;

    const visible = rows.filter(r=>!r.classList.contains('vsp-p466a3-hidden'));
    if(!visible.length) return;
    visible.sort((a,b)=>{
      const ta = extractTs(t(a));
      const tb = extractTs(t(b));
      if(ta===tb){
        const ra = extractRidFromText(t(a));
        const rb = extractRidFromText(t(b));
        return ra<rb?-1:ra>rb?1:0;
      }
      return mode==='new' ? (tb-ta) : (ta-tb);
    });

    const parent = visible[0].parentElement;
    if(!parent) return;
    for(const r of visible) parent.appendChild(r);
  }

  function highlight(root, rows){
    const sel = getSel();
    for(const r of rows){
      const rid = extractRidFromText(t(r));
      if(sel && rid === sel) r.classList.add('vsp-p466a3-selected');
      else r.classList.remove('vsp-p466a3-selected');
    }
  }

  function bind(root){
    // remember selection when clicking Use RID
    root.addEventListener('click', (ev)=>{
      const btn = ev.target && ev.target.closest ? ev.target.closest('button') : null;
      if(!btn) return;
      if(t(btn).toLowerCase() !== 'use rid') return;
      const row = rowFromUseRidButton(btn);
      const rid = row ? extractRidFromText(t(row)) : '';
      if(rid) setSel(rid);
      // apply highlight immediately
      const rows = collectRows(root);
      highlight(root, rows);
    }, true);
  }

  function apply(root){
    ensureSortSelect(root);
    const rows = collectRows(root);
    if(!rows.length) return;
    dedupe(root, rows);
    sortRows(root, rows);
    highlight(root, rows);
  }

  const root = findRunsSection();
  bind(root);

  // periodic reconcile (safe)
  setInterval(()=>apply(root), 800);
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded', ()=>setTimeout(()=>apply(root), 120));
  else setTimeout(()=>apply(root), 120);
})();
/* --- /VSP_P466A3_RUNS_DEDUPE_ANYROW_V1 --- */
'''
p.write_text(s.rstrip()+"\n\n"+addon+"\n", encoding="utf-8")
print("[OK] appended P466a3 addon")
PY

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" || true
fi

echo "[OK] P466a3 done. Hard refresh /c/runs: duplicates should disappear + Sort appears next to Filter + loaded count fixed." | tee -a "$OUT/log.txt"
