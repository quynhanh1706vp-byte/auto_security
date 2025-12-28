#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3

TS="$(date +%Y%m%d_%H%M%S)"
ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*"; }

C_COMMON="static/js/vsp_c_common_v1.js"
C_DASH="static/js/vsp_c_dashboard_v1.js"

[ -f "$C_COMMON" ] || { echo "[ERR] missing $C_COMMON"; exit 2; }
[ -f "$C_DASH" ] || { echo "[ERR] missing $C_DASH"; exit 2; }

cp -f "$C_COMMON" "${C_COMMON}.bak_p120_${TS}"
cp -f "$C_DASH"   "${C_DASH}.bak_p120_${TS}"
ok "backup: ${C_COMMON}.bak_p120_${TS}"
ok "backup: ${C_DASH}.bak_p120_${TS}"

# 1) Rewrite vsp_c_common_v1.js with stable global shim (fixes onRefresh undefined)
cat > "$C_COMMON" <<'JS'
/* VSP_P120_C_COMMON_SHIM_V1
 * Purpose:
 * - Provide a stable global window.VSPC for /c/* suite
 * - Fix: "Cannot read properties of undefined (reading 'onRefresh')"
 * - Provide refresh event bus + RID resolution (latest) + fetchJSON with timeout
 */
(function(){
  'use strict';

  const log = (...a)=>{ try{ console.log('[VSPC]', ...a); }catch(e){} };
  const warn = (...a)=>{ try{ console.warn('[VSPC]', ...a); }catch(e){} };

  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }

  function sanitizeRid(x){
    x = (x||'').toString().trim();
    // allow VSP_CI_YYYYmmdd_HHMMSS and RUN_* style, block accidental "VSP_FILL_..." junk
    if(!x) return '';
    if(x.length > 128) return '';
    if(!/^[A-Za-z0-9_.:-]+$/.test(x)) return '';
    if(/^VSP_FILL_/i.test(x)) return '';
    return x;
  }

  function getUrlParam(name){
    try{
      const u = new URL(window.location.href);
      return u.searchParams.get(name) || '';
    }catch(e){ return ''; }
  }

  function setUrlParam(name, value){
    try{
      const u = new URL(window.location.href);
      if(value) u.searchParams.set(name, value);
      else u.searchParams.delete(name);
      history.replaceState({}, '', u.toString());
    }catch(e){}
  }

  async function fetchJSON(url, opt){
    opt = opt || {};
    const timeoutMs = opt.timeoutMs || 2500;
    const ctrl = new AbortController();
    const t = setTimeout(()=>ctrl.abort(), timeoutMs);
    try{
      const r = await fetch(url, {signal: ctrl.signal, cache:'no-store', credentials:'same-origin'});
      const ct = (r.headers.get('content-type')||'').toLowerCase();
      const txt = await r.text();
      let j = null;
      if(ct.includes('application/json')){
        try{ j = JSON.parse(txt); }catch(e){ j = null; }
      }else{
        // best effort JSON parse
        try{ j = JSON.parse(txt); }catch(e){ j = null; }
      }
      return {ok: r.ok, status: r.status, json: j, text: txt, headers: r.headers};
    }catch(e){
      return {ok:false, status:0, json:null, text:String(e)};
    }finally{
      clearTimeout(t);
    }
  }

  async function resolveLatestRid(base){
    const url = `${base}/api/ui/runs_v3?limit=1&include_ci=1`;
    const r = await fetchJSON(url, {timeoutMs: 2500});
    try{
      const rid = sanitizeRid(r.json && r.json.items && r.json.items[0] && r.json.items[0].rid);
      return rid || '';
    }catch(e){ return ''; }
  }

  function dispatchRefresh(){
    try{
      window.dispatchEvent(new CustomEvent('vsp:refresh', {detail:{ts: Date.now()}}));
    }catch(e){}
  }

  function onRefresh(fn){
    window.addEventListener('vsp:refresh', (ev)=>{ try{ fn(ev); }catch(e){} });
  }

  function ensureHeaderHook(){
    // try attach refresh button (id-based first, fallback by text)
    const btn = qs('#b-refresh') || qsa('button').find(b => (b.textContent||'').trim().toUpperCase() === 'REFRESH');
    if(btn && !btn.__vspc_bound){
      btn.__vspc_bound = 1;
      btn.addEventListener('click', ()=>dispatchRefresh());
    }
  }

  function setText(id, txt){
    const el = qs('#'+id);
    if(el) el.textContent = (txt==null?'':String(txt));
  }

  const base = (function(){
    try{ return window.location.origin; }catch(e){ return ''; }
  })();

  // Export global
  window.VSPC = window.VSPC || {};
  Object.assign(window.VSPC, {
    ver: 'P120',
    base,
    sanitizeRid,
    getUrlParam,
    setUrlParam,
    fetchJSON,
    resolveLatestRid,
    onRefresh,
    dispatchRefresh,
    setText,
    ensureHeaderHook
  });

  // bind header on load
  document.addEventListener('DOMContentLoaded', ()=>{
    try{
      ensureHeaderHook();
      log('installed', window.VSPC.ver);
    }catch(e){}
  });
})();
JS
ok "wrote $C_COMMON"

# 2) Rewrite vsp_c_dashboard_v1.js: keep it light, add Tool Risk stacked bars + keep Top Findings table
cat > "$C_DASH" <<'JS'
/* VSP_P120_C_DASHBOARD_TOOL_BARS_V1
 * - Uses window.VSPC (from vsp_c_common_v1.js)
 * - Renders:
 *   KPI (Total / Top Findings total / Trend points) + Tool Risk stacked bars + Top Findings table + Trend mini (simple line)
 * - Degrade gracefully (no freeze): small timeouts + limited paging
 */
(function(){
  'use strict';

  const C = window.VSPC || {};
  const log = (...a)=>{ try{ console.log('[C-DASH]', ...a); }catch(e){} };
  const warn = (...a)=>{ try{ console.warn('[C-DASH]', ...a); }catch(e){} };

  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }
  function esc(s){ return (s==null?'':String(s)).replace(/[&<>"']/g, m=>({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[m])); }
  function byId(id){ return document.getElementById(id); }

  function ensureStyles(){
    if(byId('vsp_p120_styles')) return;
    const st = document.createElement('style');
    st.id = 'vsp_p120_styles';
    st.textContent = `
      .vsp_p120_card { border:1px solid rgba(255,255,255,.06); background: rgba(10,16,28,.55); border-radius: 14px; padding: 12px; }
      .vsp_p120_title { font-weight: 700; font-size: 12px; letter-spacing: .2px; opacity: .9; }
      .vsp_p120_sub { font-size: 11px; opacity: .7; margin-top: 2px; }
      .vsp_p120_row { display:flex; align-items:center; gap:10px; margin: 8px 0; }
      .vsp_p120_tool { width: 92px; font-size: 11px; opacity:.9; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
      .vsp_p120_bar { flex:1; height: 10px; border-radius: 10px; overflow: hidden; background: rgba(255,255,255,.06); display:flex; }
      .seg_cri { background: rgba(255,80,80,.85); }
      .seg_high { background: rgba(255,150,60,.85); }
      .seg_med { background: rgba(255,210,80,.85); }
      .seg_low { background: rgba(120,200,255,.75); }
      .seg_info { background: rgba(200,200,200,.45); }
      .vsp_p120_num { width: 54px; text-align:right; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace; font-size: 11px; opacity:.85; }
      .vsp_p120_hint { font-size: 11px; opacity: .65; margin-top: 8px; }
      .vsp_p120_tbl { width:100%; border-collapse: collapse; font-size: 11px; }
      .vsp_p120_tbl th, .vsp_p120_tbl td { border-bottom: 1px solid rgba(255,255,255,.06); padding: 6px 8px; }
      .sev_CRITICAL { color: rgba(255,110,110,.95); font-weight:700; }
      .sev_HIGH { color: rgba(255,170,90,.95); font-weight:700; }
      .sev_MEDIUM { color: rgba(255,220,120,.95); font-weight:700; }
      .sev_LOW { color: rgba(150,210,255,.95); font-weight:700; }
      .sev_INFO, .sev_TRACE { color: rgba(210,210,210,.75); }
    `;
    document.head.appendChild(st);
  }

  function pickRidFromPage(){
    const r1 = C.sanitizeRid ? C.sanitizeRid(C.getUrlParam && C.getUrlParam('rid')) : '';
    const r2 = C.sanitizeRid ? C.sanitizeRid(localStorage.getItem('vsp_rid')||'') : '';
    return r1 || r2 || '';
  }

  async function ensureRid(base){
    let rid = pickRidFromPage();
    if(!rid){
      rid = (await (C.resolveLatestRid ? C.resolveLatestRid(base) : Promise.resolve(''))) || '';
      if(rid){
        try{ localStorage.setItem('vsp_rid', rid); }catch(e){}
        if(C.setUrlParam) C.setUrlParam('rid', rid);
      }
    }
    return rid;
  }

  function getItemsFromAny(j){
    if(!j) return [];
    return j.items || j.rows || j.data || j.findings || [];
  }

  function sevKey(s){
    s = (s||'').toString().toUpperCase();
    if(s==='CRITICAL') return 'CRITICAL';
    if(s==='HIGH') return 'HIGH';
    if(s==='MEDIUM') return 'MEDIUM';
    if(s==='LOW') return 'LOW';
    if(s==='INFO') return 'INFO';
    if(s==='TRACE') return 'TRACE';
    return 'INFO';
  }

  function weight(counts){
    return (counts.CRITICAL||0)*100 + (counts.HIGH||0)*20 + (counts.MEDIUM||0)*5 + (counts.LOW||0)*2 + (counts.INFO||0) + (counts.TRACE||0)*0.5;
  }

  function ensureToolBarsCard(){
    // try mount under the mini trend card, otherwise create at top of main container
    let anchor = qs('#trend-mini')?.closest('div') || null;
    let mount = qs('#vsp_p120_toolbars');
    if(mount) return mount;

    const card = document.createElement('div');
    card.id = 'vsp_p120_toolbars';
    card.className = 'vsp_p120_card';
    card.innerHTML = `
      <div class="vsp_p120_title">Tool Risk (stacked)</div>
      <div class="vsp_p120_sub">Breakdown theo tool × severity (sampled)</div>
      <div id="vsp_p120_toolbars_body" style="margin-top:10px"></div>
      <div class="vsp_p120_hint" id="vsp_p120_toolbars_hint"></div>
    `;

    // Place it: try right column near Trend(mini)
    if(anchor && anchor.parentElement){
      anchor.parentElement.appendChild(card);
    }else{
      // fallback: append to body end
      document.body.appendChild(card);
    }
    return card;
  }

  function renderToolBars(toolMap, meta){
    const card = ensureToolBarsCard();
    const body = qs('#vsp_p120_toolbars_body', card);
    const hint = qs('#vsp_p120_toolbars_hint', card);
    if(!body || !hint) return;

    const rows = Object.keys(toolMap).map(t=>({tool:t, counts: toolMap[t], score: weight(toolMap[t])}));
    rows.sort((a,b)=>b.score-a.score);
    const top = rows.slice(0, 10);

    body.innerHTML = top.map(r=>{
      const c = r.counts;
      const total = (c.CRITICAL||0)+(c.HIGH||0)+(c.MEDIUM||0)+(c.LOW||0)+(c.INFO||0)+(c.TRACE||0) || 1;
      const p = (x)=>Math.max(0, (x||0)*100/total);
      return `
        <div class="vsp_p120_row">
          <div class="vsp_p120_tool" title="${esc(r.tool)}">${esc(r.tool)}</div>
          <div class="vsp_p120_bar" title="C:${c.CRITICAL||0} H:${c.HIGH||0} M:${c.MEDIUM||0} L:${c.LOW||0} I:${(c.INFO||0)+(c.TRACE||0)}">
            <div class="seg_cri" style="width:${p(c.CRITICAL)}%"></div>
            <div class="seg_high" style="width:${p(c.HIGH)}%"></div>
            <div class="seg_med" style="width:${p(c.MEDIUM)}%"></div>
            <div class="seg_low" style="width:${p(c.LOW)}%"></div>
            <div class="seg_info" style="width:${p((c.INFO||0)+(c.TRACE||0))}%"></div>
          </div>
          <div class="vsp_p120_num">${total}</div>
        </div>
      `;
    }).join('');

    hint.textContent = meta || '';
  }

  function findTopFindingsTableBody(){
    // Prefer known id "tb" from template; else find the Top Findings table by headers
    const tb = qs('#tb');
    if(tb){
      // tb might be tbody or wrapper
      if(tb.tagName && tb.tagName.toLowerCase()==='tbody') return tb;
      const tbb = tb.querySelector('tbody');
      if(tbb) return tbb;
    }
    const tables = qsa('table');
    for(const t of tables){
      const h = (t.innerText||'').toLowerCase();
      if(h.includes('severity') && h.includes('title') && h.includes('tool')) return t.querySelector('tbody') || t;
    }
    return null;
  }

  function renderTopFindings(items){
    const tbody = findTopFindingsTableBody();
    if(!tbody) return;

    const rows = (items||[]).map(it=>{
      const sev = sevKey(it.severity);
      const cls = 'sev_'+sev;
      const title = it.title || it.rule || it.message || '(no title)';
      const tool = it.tool || it.engine || '-';
      const file = (it.location && (it.location.path||it.location.file)) || it.file || it.component || '-';
      return `
        <tr>
          <td class="${cls}">${esc(sev)}</td>
          <td title="${esc(title)}">${esc(title)}</td>
          <td>${esc(tool)}</td>
          <td title="${esc(file)}">${esc(file)}</td>
        </tr>
      `;
    }).join('');

    // if tbody is table itself
    if(tbody.tagName && tbody.tagName.toLowerCase()==='table'){
      tbody.innerHTML = `<tbody>${rows}</tbody>`;
    }else{
      tbody.innerHTML = rows || `<tr><td colspan="4" style="opacity:.65">No data</td></tr>`;
    }
  }

  function renderMiniTrend(points){
    const box = qs('#trend-mini');
    if(!box) return;
    const w = 260, h = 70, pad = 6;
    const arr = (points||[]).map(p=>Number(p.total||p.y||p.count||0)).filter(n=>Number.isFinite(n));
    if(arr.length<2){
      box.innerHTML = `<div style="opacity:.65;font-size:11px">No trend data</div>`;
      return;
    }
    const min = Math.min(...arr), max = Math.max(...arr);
    const sx = (i)=> pad + i*(w-2*pad)/(arr.length-1);
    const sy = (v)=> {
      if(max===min) return h/2;
      return pad + (max - v) * (h-2*pad) / (max-min);
    };
    let d = '';
    arr.forEach((v,i)=>{
      d += (i===0?'M':'L') + sx(i).toFixed(1) + ',' + sy(v).toFixed(1) + ' ';
    });
    box.innerHTML = `
      <svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
        <path d="${d}" fill="none" stroke="rgba(120,200,255,.9)" stroke-width="2"/>
        <line x1="${pad}" y1="${h-pad}" x2="${w-pad}" y2="${h-pad}" stroke="rgba(255,255,255,.08)" />
      </svg>
      <div style="opacity:.7;font-size:11px;margin-top:4px">min=${min} max=${max}</div>
    `;
  }

  async function buildToolBreakdown(base, rid){
    // Prefer findings_page_v3 paging (up to 5 pages), else fallback to top_findings_v2 sample.
    const toolMap = {};
    let sampled = 0;
    let source = 'top_findings_v2 (sample)';

    async function addItems(items){
      for(const it of (items||[])){
        const tool = (it.tool||it.engine||'unknown').toString();
        const sev = sevKey(it.severity);
        toolMap[tool] = toolMap[tool] || {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
        toolMap[tool][sev] = (toolMap[tool][sev]||0)+1;
        sampled++;
      }
    }

    // Try findings_page_v3
    for(let page=0; page<5; page++){
      const off = page*200;
      const url = `${base}/api/vsp/findings_page_v3?rid=${encodeURIComponent(rid)}&limit=200&offset=${off}&path=`;
      const r = await (C.fetchJSON ? C.fetchJSON(url, {timeoutMs: 2000}) : Promise.resolve({ok:false}));
      if(!r.ok || !r.json){
        break;
      }
      const items = getItemsFromAny(r.json);
      if(items.length===0) break;
      source = 'findings_page_v3 (paged sample)';
      await addItems(items);
      if(items.length < 200) break;
      if(sampled >= 1000) break;
    }

    if(sampled===0){
      const url2 = `${base}/api/vsp/top_findings_v2?limit=200&rid=${encodeURIComponent(rid)}`;
      const r2 = await (C.fetchJSON ? C.fetchJSON(url2, {timeoutMs: 2000}) : Promise.resolve({ok:false}));
      const items2 = getItemsFromAny(r2.json);
      await addItems(items2);
    }

    const meta = `RID=${rid} • ${source} • sampled=${sampled}`;
    return {toolMap, meta};
  }

  async function loadAndRender(){
    ensureStyles();
    if(C.ensureHeaderHook) C.ensureHeaderHook();

    const base = C.base || (window.location.origin||'');
    const rid = await ensureRid(base);

    // Update header strip ids if present
    if(C.setText){
      C.setText('p-rid', rid || '(none)');
      C.setText('k-from', rid ? `RID=${rid}` : 'RID=none');
      C.setText('k-time', new Date().toLocaleString());
    }

    // 1) Top findings
    let top = {total:0, items:[]};
    {
      const url = `${base}/api/vsp/top_findings_v2?limit=20&rid=${encodeURIComponent(rid)}`;
      const r = await (C.fetchJSON ? C.fetchJSON(url, {timeoutMs: 2500}) : Promise.resolve({ok:false}));
      const j = r.json || {};
      top.total = j.total || 0;
      top.items = getItemsFromAny(j);
      renderTopFindings(top.items);
      if(C.setText) C.setText('k-toplen', String(top.total||0));
    }

    // 2) Trend
    {
      // best effort: some deployments accept rid, some not
      const urlA = `${base}/api/vsp/trend_v1?rid=${encodeURIComponent(rid)}`;
      const ra = await (C.fetchJSON ? C.fetchJSON(urlA, {timeoutMs: 2500}) : Promise.resolve({ok:false}));
      let pts = (ra.json && (ra.json.points||ra.json.items||ra.json.data)) || null;
      if(!pts){
        const urlB = `${base}/api/vsp/trend_v1`;
        const rb = await (C.fetchJSON ? C.fetchJSON(urlB, {timeoutMs: 2500}) : Promise.resolve({ok:false}));
        pts = (rb.json && (rb.json.points||rb.json.items||rb.json.data)) || [];
      }
      renderMiniTrend(pts||[]);
    }

    // 3) KPIs (best effort)
    {
      const urlA = `${base}/api/vsp/dashboard_kpis_v4?rid=${encodeURIComponent(rid)}`;
      const r = await (C.fetchJSON ? C.fetchJSON(urlA, {timeoutMs: 2500}) : Promise.resolve({ok:false}));
      const j = r.json || {};
      const total = j.total || j.findings_total || top.total || 0;
      if(C.setText) C.setText('k-total', String(total||0));
    }

    // 4) Tool bars
    {
      const br = await buildToolBreakdown(base, rid);
      renderToolBars(br.toolMap, br.meta);
    }

    log('rendered rid=', rid);
  }

  function boot(){
    loadAndRender().catch(e=>warn('load failed', e));
    if(C.onRefresh){
      C.onRefresh(()=>loadAndRender().catch(()=>{}));
    }
  }

  document.addEventListener('DOMContentLoaded', boot);
})();
JS
ok "wrote $C_DASH"

# 3) Prepend a safety shim to other /c/* modules if they exist (so they won't crash even if loaded before common)
python3 - <<'PY'
from pathlib import Path
import datetime, re

ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
targets = [
  Path("static/js/vsp_c_runs_v1.js"),
  Path("static/js/vsp_c_data_source_v1.js"),
  Path("static/js/vsp_c_settings_v1.js"),
  Path("static/js/vsp_c_rule_overrides_v1.js"),
]
shim = """/* VSP_P120_PRELUDE_SHIM_V1 */
(function(){
  if(window.VSPC) return;
  window.VSPC = {
    ver:'P120-prelude',
    base:(location && location.origin)||'',
    onRefresh:(fn)=>window.addEventListener('vsp:refresh', fn),
    dispatchRefresh:()=>{ try{ window.dispatchEvent(new CustomEvent('vsp:refresh',{detail:{ts:Date.now()}})); }catch(e){} },
  };
})();
"""
for p in targets:
  if not p.exists(): 
    continue
  s = p.read_text(encoding="utf-8", errors="replace")
  if "VSP_P120_PRELUDE_SHIM_V1" in s:
    continue
  p.rename(p.with_suffix(p.suffix + f".bak_p120_{ts}"))
  p.write_text(shim + "\n" + s, encoding="utf-8")
  print("[OK] prepended shim:", p)
PY

ok "P120 installed."

echo
echo "[NEXT] Hard refresh browser (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/dashboard?rid=<RID>"
echo "  http://127.0.0.1:8910/c/runs"
echo "  http://127.0.0.1:8910/c/data_source"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
