#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p466a_${TS}"
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
MARK="VSP_P466A_RUNS_SEARCH_SORT_KEEPSEL_V1"
if MARK in s:
    print("[OK] already patched P466a")
    raise SystemExit(0)

addon = r'''
/* --- VSP_P466A_RUNS_SEARCH_SORT_KEEPSEL_V1 --- */
(function(){
  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }

  const LS_KEY = 'vsp_runs_selected_rid_v1';

  function getSelectedRid(){
    try{ return (localStorage.getItem(LS_KEY)||'').trim(); }catch(e){ return ''; }
  }
  function setSelectedRid(rid){
    try{ localStorage.setItem(LS_KEY, String(rid||'').trim()); }catch(e){}
  }

  function getRidFromRow(row){
    if(!row) return '';
    const rid = (row.getAttribute('data-vsp-rid') || row.getAttribute('data-rid') || '').trim();
    if(rid) return rid;
    // try first cell text
    const td = row.querySelector('td');
    if(td){
      const t = (td.textContent||'').trim();
      // basic heuristic: RID often starts with VSP_
      if(t.startsWith('VSP_')) return t;
    }
    return '';
  }

  function markSelectedRow(container){
    const want = getSelectedRid();
    if(!want) return;
    const rows = qsa('tr', container);
    for(const r of rows){
      const rid = getRidFromRow(r);
      if(rid && rid === want){
        r.classList.add('vsp-p466a-selected');
      }else{
        r.classList.remove('vsp-p466a-selected');
      }
    }
  }

  function ensureStyles(){
    if(qs('#vsp_p466a_css')) return;
    const st=document.createElement('style');
    st.id='vsp_p466a_css';
    st.textContent = `
      .vsp-p466a-toolbar{ display:flex; gap:10px; align-items:center; flex-wrap:wrap; margin: 10px 0; }
      .vsp-p466a-inp{ padding:8px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); color:#fff; min-width: 240px; }
      .vsp-p466a-sel{ padding:8px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); color:#fff; }
      tr.vsp-p466a-selected{ outline: 2px solid rgba(255,255,255,.14); background: rgba(255,255,255,.04) !important; }
      .vsp-p466a-hidden{ display:none !important; }
    `;
    document.head.appendChild(st);
  }

  function findRunsTableRoot(){
    // try common runs containers
    return qs('#vsp_runs_root')
      || qs('#vsp_runs')
      || qs('#runs_root')
      || qs('.vsp-runs-root')
      || qs('#vsp_p464c_exports_mount')?.parentElement
      || qs('main')
      || document.body;
  }

  function findTable(container){
    // pick the biggest table in runs area
    const tables = qsa('table', container);
    if(!tables.length) return null;
    let best = tables[0], bestRows = qsa('tr', best).length;
    for(const t of tables){
      const n = qsa('tr', t).length;
      if(n > bestRows){ best=t; bestRows=n; }
    }
    return best;
  }

  function parseEpochFromRowText(row){
    const txt = (row.textContent||'');
    // heuristic: if text contains YYYY-MM-DD or YYYY/MM/DD
    const m = txt.match(/(20\d{2})[-\/](\d{2})[-\/](\d{2})/);
    if(!m) return 0;
    const y=+m[1], mo=+m[2], d=+m[3];
    // treat as local midnight
    const dt = new Date(y, mo-1, d, 0,0,0,0);
    return dt.getTime() || 0;
  }

  function ensureToolbar(container, table){
    ensureStyles();
    if(qs('.vsp-p466a-toolbar', container)) return;

    const bar=document.createElement('div');
    bar.className='vsp-p466a-toolbar';

    const inp=document.createElement('input');
    inp.className='vsp-p466a-inp';
    inp.placeholder='Search runs (rid / status / target / date...)';
    inp.autocomplete='off';

    const sel=document.createElement('select');
    sel.className='vsp-p466a-sel';
    sel.innerHTML = `
      <option value="new">Sort: Newest</option>
      <option value="old">Sort: Oldest</option>
    `;

    bar.appendChild(inp);
    bar.appendChild(sel);

    // insert above table
    table.parentElement.insertBefore(bar, table);

    function apply(){
      const q=(inp.value||'').trim().toLowerCase();
      const rows=qsa('tbody tr', table);
      // filter
      for(const r of rows){
        const t=(r.textContent||'').toLowerCase();
        if(!q || t.includes(q)) r.classList.remove('vsp-p466a-hidden');
        else r.classList.add('vsp-p466a-hidden');
      }
      // sort (stable within visible)
      const visible = rows.filter(r=>!r.classList.contains('vsp-p466a-hidden'));
      visible.sort((a,b)=>{
        const ta=parseEpochFromRowText(a);
        const tb=parseEpochFromRowText(b);
        // fallback: rid text compare
        if(ta===tb){
          const ra=getRidFromRow(a), rb=getRidFromRow(b);
          return (ra<rb?-1:ra>rb?1:0);
        }
        return sel.value==='new' ? (tb-ta) : (ta-tb);
      });
      const tb = qs('tbody', table) || table;
      for(const r of visible) tb.appendChild(r);

      markSelectedRow(table);
    }

    inp.addEventListener('input', ()=>{ apply(); });
    sel.addEventListener('change', ()=>{ apply(); });

    // click -> remember selected rid
    table.addEventListener('click', (ev)=>{
      const tr = ev.target && ev.target.closest ? ev.target.closest('tr') : null;
      if(!tr) return;
      const rid=getRidFromRow(tr);
      if(rid){ setSelectedRid(rid); markSelectedRow(table); }
    });

    // initial apply
    setTimeout(apply, 80);
  }

  function hook(){
    const root=findRunsTableRoot();
    const table=findTable(root);
    if(!table) return;
    ensureToolbar(root, table);
    markSelectedRow(table);
  }

  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded', hook);
  else hook();

  setInterval(hook, 1200);
})();
/* --- /VSP_P466A_RUNS_SEARCH_SORT_KEEPSEL_V1 --- */
'''
p.write_text(s.rstrip()+"\n\n"+addon+"\n", encoding="utf-8")
print("[OK] appended P466a addon")
PY

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" || true
fi

echo "[OK] P466a done. Refresh /runs: you should see Search + Sort above runs table." | tee -a "$OUT/log.txt"
