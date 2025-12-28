#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JSF="static/js/vsp_runs_overall_from_gate_shim_p0_v2.js"
TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "$TPL.bak_overallshimv2_${TS}" && echo "[BACKUP] $TPL.bak_overallshimv2_${TS}"
[ -f "$JSF" ] && cp -f "$JSF" "$JSF.bak_${TS}" && echo "[BACKUP] $JSF.bak_${TS}"

cat > "$JSF" <<'JS'
(function(){
  'use strict';
  if (window.__VSP_RUNS_OVERALL_SHIM_P0_V2) return;
  window.__VSP_RUNS_OVERALL_SHIM_P0_V2 = true;

  const TAG='VSP_RUNS_OVERALL_SHIM_P0_V2';
  const RID_RE=/\bVSP_[A-Z0-9]+_\d{8}_\d{6}\b/;
  const cache=new Map(); // rid->overall

  function ensureStyle(){
    if (document.getElementById('vsp-ov-style-v2')) return;
    const st=document.createElement('style');
    st.id='vsp-ov-style-v2';
    st.textContent=`
      .vsp-ov-bdg{display:inline-flex;align-items:center;justify-content:center;
        padding:4px 10px;border-radius:999px;font-size:12px;font-weight:900;
        border:1px solid rgba(255,255,255,.14);letter-spacing:.2px}
      .vsp-ov-green{background:rgba(0,255,140,.12)}
      .vsp-ov-amber{background:rgba(255,190,0,.14)}
      .vsp-ov-red{background:rgba(255,70,70,.14)}
      .vsp-ov-na{background:rgba(160,160,160,.14)}
    `;
    document.head.appendChild(st);
  }

  function normOverall(v){
    v=String(v||'').toUpperCase();
    if (v==='OK') return 'GREEN';
    if (v==='FAIL') return 'RED';
    if (v==='DEGRADED') return 'AMBER';
    return v || 'N/A';
  }
  function cls(v){
    v=normOverall(v);
    if (v==='GREEN') return 'vsp-ov-green';
    if (v==='AMBER') return 'vsp-ov-amber';
    if (v==='RED') return 'vsp-ov-red';
    return 'vsp-ov-na';
  }

  async function fetchOverall(rid){
    if (!rid) return '';
    if (cache.has(rid)) return cache.get(rid)||'';
    try{
      const r=await fetch(`/api/vsp/run_gate_summary_v1/${encodeURIComponent(rid)}`, {credentials:'same-origin'});
      const j=await r.json().catch(()=>null);
      const ov = j ? (j.overall?.status || j.overall || '') : '';
      const v = normOverall(ov);
      cache.set(rid, v);
      return v;
    }catch(_){
      cache.set(rid,'');
      return '';
    }
  }

  function findRunsTable(){
    // pick the first big table in view (runs list)
    const tables=[...document.querySelectorAll('table')];
    return tables.find(t => (t.innerText||'').includes('RUN ID') && (t.innerText||'').includes('OVERALL')) || tables[0] || null;
  }

  function headerIndex(table, name){
    const ths=[...table.querySelectorAll('thead th, thead td, th')];
    for (let i=0;i<ths.length;i++){
      const tx=(ths[i].innerText||'').trim().toUpperCase();
      if (tx===name) return i;
    }
    return -1;
  }

  function cellAt(row, idx){
    const tds=[...row.querySelectorAll('td')];
    return (idx>=0 && idx<tds.length) ? tds[idx] : null;
  }

  async function patchOnce(){
    ensureStyle();
    const table=findRunsTable();
    if (!table) return;

    const idxOverall = headerIndex(table,'OVERALL');
    if (idxOverall < 0) return;

    const rows=[...table.querySelectorAll('tbody tr')];
    let changed=0;

    for (const tr of rows){
      const txt=(tr.innerText||'').match(RID_RE);
      const rid=txt && txt[0] ? txt[0] : '';
      if (!rid) continue;

      const td=cellAt(tr, idxOverall);
      if (!td) continue;

      const cur=(td.innerText||'').trim().toUpperCase();
      if (cur && cur !== 'N/A') continue;

      const ov=await fetchOverall(rid);
      if (!ov) continue;

      td.classList.add('vsp-ov-bdg');
      td.classList.remove('vsp-ov-green','vsp-ov-amber','vsp-ov-red','vsp-ov-na');
      td.classList.add(cls(ov));
      td.innerText = ov;
      td.title = `RID=${rid}`;
      changed++;
    }

    if (changed) console.log(`[${TAG}] patched`, changed, 'overall cells');
  }

  function boot(){
    let ticks=0;
    const iv=setInterval(async ()=>{
      ticks++;
      await patchOnce();
      if (ticks>=30) clearInterval(iv); // ~15s max
    }, 500);
  }

  if (document.readyState==='loading') document.addEventListener('DOMContentLoaded', boot, {once:true});
  else boot();
})();
JS

python3 - <<'PY'
from pathlib import Path
import re, datetime
tpl=Path("templates/vsp_dashboard_2025.html")
t=tpl.read_text(encoding="utf-8", errors="ignore")
if "vsp_runs_overall_from_gate_shim_p0_v2.js" not in t:
  stamp=datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
  tag=f'<script src="/static/js/vsp_runs_overall_from_gate_shim_p0_v2.js?v={stamp}" defer></script>'
  t=re.sub(r"</body>", tag+"\n</body>", t, count=1, flags=re.I)
  tpl.write_text(t, encoding="utf-8")
  print("[OK] injected overall shim v2")
else:
  print("[OK] overall shim v2 already injected")
PY

node --check "$JSF" >/dev/null && echo "[OK] node --check"
echo "[OK] patched overall shim v2"
echo "[NEXT] restart UI + hard refresh"
