#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== PATCH DASHBOARD TREND SPARKLINE (V2) =="

F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_trend_v2_${TS}" && echo "[BACKUP] $F.bak_trend_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

BEGIN="/* VSP_DASH_TREND_SPARKLINE_V2_BEGIN */"
END  ="/* VSP_DASH_TREND_SPARKLINE_V2_END */"
s=re.sub(re.escape(BEGIN)+r"[\s\S]*?"+re.escape(END)+r"\n?", "", s, flags=re.M)

block = r'''
/* VSP_DASH_TREND_SPARKLINE_V2_BEGIN */
(function(){
  'use strict';

  function $(sel){ return document.querySelector(sel); }
  function el(tag, cls){ const e=document.createElement(tag); if(cls) e.className=cls; return e; }
  function sstr(x){ return (typeof x === 'string') ? x.trim() : ''; }

  function findKpiMount(){
    // try common containers (robust across templates)
    const cands = [
      '#vsp-kpi-row', '#kpi-row', '#kpi-cards', '.vsp-kpi-row', '.kpi-row',
      '.vsp-kpi-grid', '.kpi-grid', '.dashboard-kpis', '.dashboard-kpi-grid',
      '.vsp-main .vsp-grid', '.vsp-main'
    ];
    for (const sel of cands){
      const n = document.querySelector(sel);
      if (n) return n;
    }
    // fallback: first large section in dashboard pane
    return document.querySelector('#pane-dashboard, #tab-dashboard, main') || document.body;
  }

  async function fetchRuns(){
    try{
      const res = await fetch('/api/vsp/runs_index_v3_fs_resolved?limit=12&hide_empty=0&filter=1', {credentials:'same-origin'});
      if (!res.ok) return [];
      const js = await res.json();
      return js.items || [];
    }catch(_e){
      return [];
    }
  }

  function parseKeyFromRid(rid){
    rid = sstr(rid);
    const m = rid.match(/(\d{8})_(\d{6})/);
    if (!m) return null;
    return m[1] + m[2];
  }

  function buildSeries(items){
    // sort ascending by rid timestamp
    const arr = (items||[]).map(it=>{
      const rid = sstr(it.run_id || it.rid || '');
      const key = parseKeyFromRid(rid) || rid;
      const v = Number(it.total_findings ?? it.findings_total ?? it.total ?? 0) || 0;
      return {rid, key, v};
    }).filter(x=>x.rid && x.key).sort((a,b)=> (a.key>b.key?1:(a.key<b.key?-1:0)));
    // keep last 10
    return arr.slice(Math.max(0, arr.length-10));
  }

  function drawSpark(canvas, series){
    const ctx = canvas.getContext('2d');
    const w = canvas.width, h = canvas.height;
    ctx.clearRect(0,0,w,h);

    if (!series || series.length < 2){
      // empty state
      ctx.globalAlpha = 0.5;
      ctx.beginPath();
      ctx.moveTo(6, h/2);
      ctx.lineTo(w-6, h/2);
      ctx.stroke();
      ctx.globalAlpha = 1;
      return;
    }

    const vals = series.map(x=>x.v);
    let vmin = Math.min.apply(null, vals);
    let vmax = Math.max.apply(null, vals);
    if (vmax === vmin) vmax = vmin + 1;

    const pad = 6;
    const dx = (w - pad*2) / (series.length - 1);

    ctx.lineWidth = 2;
    ctx.beginPath();
    for (let i=0;i<series.length;i++){
      const v = series[i].v;
      const x = pad + i*dx;
      const y = pad + (h - pad*2) * (1 - (v - vmin) / (vmax - vmin));
      if (i===0) ctx.moveTo(x,y); else ctx.lineTo(x,y);
    }
    ctx.stroke();

    // end dot
    const last = series[series.length-1].v;
    const x = pad + (series.length-1)*dx;
    const y = pad + (h - pad*2) * (1 - (last - vmin) / (vmax - vmin));
    ctx.beginPath(); ctx.arc(x,y,3,0,Math.PI*2); ctx.fill();
  }

  function ensureCard(){
    const id = 'vsp-trend-spark-card-v2';
    let card = document.getElementById(id);
    if (card) return card;

    const mount = findKpiMount();

    card = el('div', 'vsp-card dashboard-card');
    card.id = id;
    card.style.maxWidth = '420px';
    card.style.padding = '12px 14px';
    card.style.borderRadius = '14px';
    card.style.margin = '8px 8px 8px 0';

    const h = el('div');
    h.style.display='flex';
    h.style.justifyContent='space-between';
    h.style.alignItems='baseline';
    h.style.gap='10px';

    const title = el('div');
    title.innerHTML = '<div style="font-weight:700;letter-spacing:.2px">Trend (last 10)</div><div style="opacity:.7;font-size:12px">Total findings by run</div>';

    const stat = el('div');
    stat.id = 'vsp-trend-spark-stat-v2';
    stat.style.textAlign='right';
    stat.style.fontWeight='700';

    h.appendChild(title);
    h.appendChild(stat);

    const canvas = el('canvas');
    canvas.id = 'vsp-trend-spark-cv-v2';
    canvas.width = 360;
    canvas.height = 64;
    canvas.style.width = '100%';
    canvas.style.height = '64px';
    canvas.style.marginTop = '10px';
    canvas.style.borderRadius = '10px';

    card.appendChild(h);
    card.appendChild(canvas);

    // prepend so it appears early
    if (mount && mount.firstChild) mount.insertBefore(card, mount.firstChild);
    else (mount || document.body).appendChild(card);

    return card;
  }

  async function render(){
    const card = ensureCard();
    if (!card) return;

    const items = await fetchRuns();
    const series = buildSeries(items);

    const stat = document.getElementById('vsp-trend-spark-stat-v2');
    const cv = document.getElementById('vsp-trend-spark-cv-v2');

    if (stat){
      const n = series.length;
      const last = n ? series[n-1].v : 0;
      const prev = n>1 ? series[n-2].v : 0;
      const delta = (n>1) ? (last - prev) : 0;
      const pct = (n>1 && prev) ? (delta * 100.0 / prev) : 0;
      stat.innerHTML = `<div style="font-size:16px">${last.toLocaleString()}</div><div style="opacity:.75;font-size:12px">${(delta>=0?'+':'')}${delta.toLocaleString()} (${(pct>=0?'+':'')}${pct.toFixed(1)}%)</div>`;
    }
    if (cv && cv.getContext) drawSpark(cv, series);
  }

  // run on dashboard load and also after refresh clicks
  document.addEventListener('DOMContentLoaded', function(){
    setTimeout(render, 650);
    document.addEventListener('click', function(ev){
      const t = ev.target;
      if (!t) return;
      const txt = (t.textContent||'').toLowerCase();
      if (txt.includes('refresh')) setTimeout(render, 400);
    }, true);
  });
})();
 /* VSP_DASH_TREND_SPARKLINE_V2_END */
'''.lstrip()

s = s.rstrip() + "\n\n" + block + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended trend sparkline v2")
PY

node --check "$F" >/dev/null && echo "[OK] dashboard enhance JS syntax OK"
echo "[DONE] Trend sparkline v2 applied. Hard refresh Ctrl+Shift+R"
