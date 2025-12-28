#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F_RUNS="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p482b_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0
command -v sudo >/dev/null 2>&1 || true

[ -f "$F_RUNS" ] || { echo "[ERR] missing $F_RUNS" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F_RUNS" "$OUT/vsp_c_runs_v1.js.bak_${TS}"
cp -f "$F_RUNS" "${F_RUNS}.bak_p482b_${TS}"
echo "[OK] backup => ${F_RUNS}.bak_p482b_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
p=Path("static/js/vsp_c_runs_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P482B_RUNS_TOOLBAR_V2_FOR_LIST_V1"
if MARK in s:
    print("[OK] already patched P482b")
else:
    js = r"""
/* VSP_P482B_RUNS_TOOLBAR_V2_FOR_LIST_V1
 * Purpose: Runs tab is list-based (rows with 'Use RID' buttons), not a table.
 * - Hide legacy inner toolbar (if any)
 * - Add toolbar V2 (filter/status/sort) and apply to list rows
 */
(function(){
  function onReady(fn){
    if(document.readyState === 'complete' || document.readyState === 'interactive') return fn();
    document.addEventListener('DOMContentLoaded', fn, {once:true});
  }

  function injectCss(){
    if(document.getElementById('vsp-runs-toolbar-v2-css')) return;
    const st=document.createElement('style');
    st.id='vsp-runs-toolbar-v2-css';
    st.textContent = `
      .vsp-runs-toolbar-v2{
        display:flex; gap:8px; align-items:center; flex-wrap:wrap;
        padding:10px 12px; margin:10px 0 12px 0;
        border:1px solid rgba(255,255,255,.08);
        background: rgba(0,0,0,.18);
        border-radius: 12px;
        position: sticky; top: 10px; z-index: 20;
        backdrop-filter: blur(10px);
      }
      .vsp-runs-toolbar-v2 input, .vsp-runs-toolbar-v2 select{
        height: 32px; border-radius: 10px;
        border:1px solid rgba(255,255,255,.10);
        background: rgba(0,0,0,.25);
        color: #dfe7ff;
        padding: 0 10px;
        outline: none;
      }
      .vsp-runs-toolbar-v2 input{ min-width: 260px; }
      .vsp-runs-toolbar-v2 .btn{
        height:32px; padding:0 10px; border-radius:10px;
        border:1px solid rgba(255,255,255,.12);
        background: rgba(0,0,0,.22);
        color:#dfe7ff; cursor:pointer;
      }
      .vsp-runs-toolbar-v2 .btn:hover{ border-color: rgba(255,255,255,.22); }
      .vsp-runs-toolbar-v2 .hint{ opacity:.75; font-size:12px; margin-left:auto; }
      .vsp-hide-legacy{ display:none !important; }
    `;
    document.head.appendChild(st);
  }

  function findRunsPanel(){
    // Try to locate panel by heading text
    const nodes=[...document.querySelectorAll('h1,h2,h3,div,span')];
    for(const el of nodes){
      const t=(el.textContent||'').trim();
      if(/Runs\s*&\s*Reports/i.test(t) || /^Runs$/i.test(t)){
        return el.closest('section,article,div') || el.parentElement || document.body;
      }
    }
    // Fallback: page content container
    return document.querySelector('#app') ||
           document.querySelector('.vsp-page') ||
           document.querySelector('.content') ||
           document.body;
  }

  function hideLegacyToolbar(panel){
    // Hide old/legacy controls that commonly exist above the list
    const all=[...panel.querySelectorAll('input,select,button,div,span')];
    for(const el of all){
      const t=(el.textContent||'').trim();
      const ph=(el.getAttribute && el.getAttribute('placeholder')) or ''
      if(/Open\s+Exports/i.test(t) ||
         /Search\s+RID/i.test(ph) ||
         /Open\s+Exports/i.test(ph) ||
         /legacy/i.test(t) ||
         /tmp/i.test(t) && /export/i.test(t)){
        const box = el.closest('div,section,article') || el;
        box.classList.add('vsp-hide-legacy');
      }
    }
  }

  function uniq(arr){
    const s=new Set(); const out=[];
    for(const x of arr){ if(x && !s.has(x)){ s.add(x); out.push(x); } }
    return out;
  }

  function closestRowFromButton(btn){
    return btn.closest('tr,[role="row"],li,.vsp-run-row,.run-row,.row,div') || btn.parentElement;
  }

  function getRows(panel){
    // Primary: rows that contain the "Use RID" button
    const useBtns=[...panel.querySelectorAll('button')].filter(b => /Use\s*RID/i.test((b.textContent||'')));
    if(useBtns.length){
      const rows=useBtns.map(closestRowFromButton);
      // avoid selecting a too-high container: keep those that actually contain that button and some RID-like token
      const filtered=[];
      for(const r of rows){
        const tx=(r.textContent||'');
        if(/VSP[_-]CI/i.test(tx) || /VSP[_-]\w+/i.test(tx)) filtered.push(r);
        else filtered.append(r)
      }
      return uniq(filtered.length?filtered:rows);
    }

    // Fallback: repeated items that look like run rows
    const cand=[...panel.querySelectorAll('[data-rid],.vsp-run-row,.run-row')];
    return uniq(cand);
  }

  function parseRid(text){
    const m = (text||'').match(/\b(VSP[_-][A-Za-z0-9_:-]+)\b/);
    return m ? m[1] : '';
  }

  function parseDate(text){
    // Try ISO-like date first
    const m = (text||'').match(/\b(20\d{2}-\d{2}-\d{2})\b/);
    return m ? m[1] : '';
  }

  function parseStatus(text){
    const tx=(text||'').toUpperCase();
    if(tx.includes('OK')) return 'OK';
    if(tx.includes('FAIL')) return 'FAIL';
    if(tx.includes('DEGRADED')) return 'DEGRADED';
    if(tx.includes('RUNNING')) return 'RUNNING';
    if(tx.includes('UNKNOWN')) return 'UNKNOWN';
    return 'UNKNOWN';
  }

  function ensureToolbar(panel){
    if(panel.querySelector('.vsp-runs-toolbar-v2')) return panel.querySelector('.vsp-runs-toolbar-v2');

    const bar=document.createElement('div');
    bar.className='vsp-runs-toolbar-v2';

    const q=document.createElement('input');
    q.type='text';
    q.placeholder='Filter (RID / date / status)…';

    const st=document.createElement('select');
    st.innerHTML = `
      <option value="">Status: ALL</option>
      <option value="OK">OK</option>
      <option value="FAIL">FAIL</option>
      <option value="DEGRADED">DEGRADED</option>
      <option value="RUNNING">RUNNING</option>
      <option value="UNKNOWN">UNKNOWN</option>
    `;

    const sort=document.createElement('select');
    sort.innerHTML = `
      <option value="newest">Sort: Newest</option>
      <option value="oldest">Sort: Oldest</option>
      <option value="rid_asc">Sort: RID A→Z</option>
      <option value="rid_desc">Sort: RID Z→A</option>
    `;

    const btnClear=document.createElement('button');
    btnClear.className='btn';
    btnClear.textContent='Clear';

    const btnRefresh=document.createElement('button');
    btnRefresh.className='btn';
    btnRefresh.textContent='Refresh';

    const hint=document.createElement('div');
    hint.className='hint';
    hint.textContent='rows: 0';

    bar.append(q, st, sort, btnClear, btnRefresh, hint);

    // insert near top of panel content
    const first = panel.querySelector('div,section,article') || panel;
    first.insertBefore(bar, first.firstChild);

    function apply(){
      const rows=getRows(panel);
      const needle=(q.value||'').trim().toLowerCase();
      const stv=(st.value||'').trim().toUpperCase();

      let visible=[];
      for(const r of rows){
        const tx=(r.textContent||'');
        const rid=parseRid(tx);
        const date=parseDate(tx);
        const status=parseStatus(tx);

        const hay=(tx + ' ' + rid + ' ' + date + ' ' + status).toLowerCase();
        let ok=true;
        if(needle && !hay.includes(needle)) ok=false;
        if(stv and status != stv) ok=false;

        r.style.display = ok ? '' : 'none';
        if(ok) visible.append(r)
      }

      // Sort visible rows by moving nodes (keeps actions intact)
      const mode=sort.value||'newest';
      def keyOf(r):
        tx=(r.textContent||'')
        rid=parseRid(tx)
        date=parseDate(tx) or ''
        return (date, rid, tx)
      try:
        if(mode=='rid_asc'):
          visible.sort(key=lambda r: parseRid((r.textContent||'')).lower())
        elif(mode=='rid_desc'):
          visible.sort(key=lambda r: parseRid((r.textContent||'')).lower(), reverse=True)
        elif(mode=='oldest'):
          visible.sort(key=lambda r: (parseDate((r.textContent||'')) or '9999-99-99'))
        else:
          visible.sort(key=lambda r: (parseDate((r.textContent||'')) or ''), reverse=True)
      except Exception:
        pass

      // Re-append in order inside their common parent if possible
      if(visible){
        # find best parent: the parent that contains most visible rows
        parents={}
        for r in visible:
          p=r.parentElement
          if p: parents[p]=parents.get(p,0)+1
        best=None
        if parents:
          best=max(parents, key=parents.get)
        if best:
          for r in visible:
            try: best.appendChild(r)
            except Exception: pass
      }

      hint.textContent = f"rows: {len(visible)}/{len(rows)}"
    }

    q.addEventListener('input', apply);
    st.addEventListener('change', apply);
    sort.addEventListener('change', apply);
    btnClear.addEventListener('click', function(){
      q.value=''; st.value=''; sort.value='newest'; apply();
    });
    btnRefresh.addEventListener('click', function(){
      // Try clicking existing refresh button in the page, else reload
      const btns=[...panel.querySelectorAll('button')];
      const b=btns.find(x => /refresh/i.test((x.textContent||'')) && x!==btnRefresh);
      if(b) b.click(); else location.reload();
    });

    // First apply after small delay (to let runs load)
    setTimeout(apply, 250);
    setTimeout(apply, 900);
    return bar;
  }

  onReady(function(){
    injectCss();
    const panel=findRunsPanel();
    hideLegacyToolbar(panel);
    const bar=ensureToolbar(panel);
    console.log('[P482b] runs toolbar V2 ready');
  });
})();
"""
    # Append safely
    s2 = s.rstrip() + "\n\n" + js + "\n"
    p.write_text(s2, encoding="utf-8")
    print("[OK] patched P482b into vsp_c_runs_v1.js")
PY

if [ "${HAS_NODE}" = "1" ]; then
  node --check "$F_RUNS" >/dev/null 2>&1 && echo "[OK] node --check ok" | tee -a "$OUT/log.txt" || { echo "[ERR] node --check failed" | tee -a "$OUT/log.txt"; exit 2; }
else
  echo "[WARN] node not found; skip syntax check" | tee -a "$OUT/log.txt"
fi

echo "[INFO] restart ${SVC}" | tee -a "$OUT/log.txt"
sudo systemctl restart "$SVC" 2>/dev/null || true
systemctl is-active "$SVC" 2>/dev/null || true

echo "[OK] P482b done. Close tab /c/runs, reopen then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
