/* VSP_DASHBOARD_CHARTS_BOOTSTRAP_V1 (P0 commercial v2)
 * - bounded retries
 * - always attempts initAll (even if container heuristic fails)
 * - empty-state has safe fallback mount (main/body) => no "missing chart container" warn
 */
(function(){
  'use strict';

  if (window.__VSP_CHARTS_BOOT_SAFE_V4) return;
  window.__VSP_CHARTS_BOOT_SAFE_V4 = true;

  const TAG = 'VSP_CHARTS_BOOT_SAFE_V4';
  const MAX_TRIES = 8;
  const BASE_DELAY_MS = 250;

  let tries = 0;
  let locked = false;
  let lastReason = '';
  let warnedOnce = false;

  const SELS = [
    '#vsp_charts_root',
    '#vsp_charts_container',
    '#vsp-dashboard-charts',
    '#dashboard_charts',
    '#charts_container',
    '#chart-container',
    '.vsp-charts',
    '[data-vsp-charts]',
    '[data-vsp-charts-root]'
  ];

  function nowISO(){ try { return new Date().toISOString(); } catch(_) { return ''; } }

  function esc(s){
    return String(s ?? '')
      .replaceAll('&','&amp;')
      .replaceAll('<','&lt;')
      .replaceAll('>','&gt;')
      .replaceAll('"','&quot;')
      .replaceAll("'","&#039;");
  }

  function pickMount(){
    // 1) explicit known selectors
    for (const s of SELS){
      const el = document.querySelector(s);
      if (el) return el;
    }

    // 2) heuristic: find chart cards by common classes
    const card = document.querySelector('.vsp-card .chart, .dashboard-card .chart, .vsp-card, .dashboard-card');
    if (card) return card;

    // 3) safe fallback: main/app/root/body (commercial: always render somewhere)
    return document.querySelector('main') ||
           document.querySelector('#app') ||
           document.querySelector('#root') ||
           document.body;
  }

  function ensureStyles(){
    if (document.getElementById('vsp-charts-empty-style-v2')) return;
    const st = document.createElement('style');
    st.id = 'vsp-charts-empty-style-v2';
    st.textContent = `
      .vsp-charts-empty{border:1px solid rgba(255,255,255,.10);background:rgba(255,255,255,.03);
        border-radius:14px;padding:14px;margin-top:10px}
      .vsp-charts-empty-hd{display:flex;align-items:center;justify-content:space-between;gap:10px}
      .vsp-charts-empty-title{font-weight:800;letter-spacing:.2px}
      .vsp-charts-empty-sub{margin-top:6px;font-size:12px;opacity:.85;display:grid;gap:4px}
      .vsp-charts-empty-reason{font-size:12px;opacity:.75}
      .vsp-charts-empty-btn{margin-top:10px;display:inline-flex;align-items:center;gap:8px;
        padding:7px 10px;border-radius:999px;border:1px solid rgba(255,255,255,.14);
        background:rgba(255,255,255,.06);cursor:pointer;font-weight:700;font-size:12px}
      .vsp-charts-empty-btn:hover{background:rgba(255,255,255,.10)}
      .vsp-charts-empty-pill{font-size:12px;font-weight:900;padding:5px 10px;border-radius:999px;
        border:1px solid rgba(255,255,255,.12);background:rgba(255,190,0,.14)}
    `;
    document.head.appendChild(st);
  }

  function renderEmptyState(reason){
    ensureStyles();
    const mount = pickMount();

    const html = `
      <div class="vsp-charts-empty" data-vsp-charts-empty="1">
        <div class="vsp-charts-empty-hd">
          <div class="vsp-charts-empty-title">Charts</div>
          <div class="vsp-charts-empty-pill">WAITING</div>
        </div>
        <div class="vsp-charts-empty-sub">
          <div class="vsp-charts-empty-reason">${esc(reason || 'waiting for chart data')}</div>
          <div>Updated: ${esc(nowISO())}</div>
        </div>
        <button class="vsp-charts-empty-btn" type="button" id="vspChartsRetryBtn">Retry charts</button>
      </div>
    `;

    const existing = mount.querySelector ? mount.querySelector('[data-vsp-charts-empty="1"]') : null;
    if (existing){
      const rr = existing.querySelector('.vsp-charts-empty-reason');
      if (rr) rr.textContent = reason || 'waiting for chart data';
    } else if (mount && mount.prepend){
      const w = document.createElement('div');
      w.innerHTML = html;
      mount.prepend(w.firstElementChild);
    }

    const btn = (mount && mount.querySelector) ? mount.querySelector('#vspChartsRetryBtn') : null;
    if (btn && !btn.__bound){
      btn.__bound = true;
      btn.addEventListener('click', function(){
        tries = 0; locked = false;
        scheduleTry('manual retry');
      });
    }
  }

  function clearEmptyState(){
    const mount = pickMount();
    const el = (mount && mount.querySelector) ? mount.querySelector('[data-vsp-charts-empty="1"]') : null;
    if (el) el.remove();
  }

  function pickEngine(){
    if (window.VSP_CHARTS_ENGINE_V3 && typeof window.VSP_CHARTS_ENGINE_V3.initAll === 'function'){
      return { tag:'VSP_CHARTS_ENGINE_V3', eng: window.VSP_CHARTS_ENGINE_V3 };
    }
    if (window.VSP_CHARTS_ENGINE && typeof window.VSP_CHARTS_ENGINE.initAll === 'function'){
      return { tag:'VSP_CHARTS_ENGINE', eng: window.VSP_CHARTS_ENGINE };
    }
    if (typeof window.vspChartsInitAll === 'function'){
      return { tag:'window.vspChartsInitAll', eng: { initAll: window.vspChartsInitAll } };
    }
    return null;
  }

  function computeDelay(n){ return Math.min(1200, BASE_DELAY_MS + (n * 120)); }

  async function tryInit(reasonTag){
    if (locked) return false;
    locked = true;
    tries += 1;

    const pe = pickEngine();
    if (!pe){
      lastReason = 'charts module not loaded (engine missing)';
      locked = false;
      return false;
    }

    try{
      pe.eng.initAll(reasonTag || TAG);
      clearEmptyState();
      console.log(`[${TAG}] initAll OK via`, pe.tag, 'tries=', tries);
      return true;
    } catch(e){
      lastReason = `initAll failed: ${e && e.message ? e.message : String(e)}`;
      if (!warnedOnce){
        warnedOnce = true;
        console.warn(`[${TAG}] initAll failed (bounded retry)`, e);
      }
      locked = false;
      return false;
    }
  }

  function scheduleTry(tag){
    const delay = computeDelay(tries);
    setTimeout(async () => {
      const ok = await tryInit(tag);
      if (ok) return;

      if (tries >= MAX_TRIES){
        renderEmptyState(lastReason || `no chart data (tries=${tries}/${MAX_TRIES})`);
        console.log(`[${TAG}] done: empty-state shown; tries=${tries}/${MAX_TRIES}; reason=`, lastReason);
        return;
      }

      renderEmptyState(lastReason || `waiting for chart data (tries=${tries}/${MAX_TRIES})`);
      scheduleTry(tag);
    }, delay);
  }

  function boot(){
    tries = 0; locked = false; lastReason = ''; warnedOnce = false;
    scheduleTry('boot');
  }

  window.VSP_CHARTS_BOOT_SAFE_V4 = { boot, refresh: () => scheduleTry('refresh') };

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', boot, { once:true });
  } else {
    boot();
  }

  window.addEventListener('vsp:rid_changed', () => scheduleTry('rid_changed'));
})();
