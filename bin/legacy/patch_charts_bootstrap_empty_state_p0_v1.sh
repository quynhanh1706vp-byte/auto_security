#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_charts_bootstrap_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_p0_charts_empty_${TS}"
echo "[BACKUP] $F.bak_p0_charts_empty_${TS}"

cat > "$F" <<'JS'
/* VSP_DASHBOARD_CHARTS_BOOTSTRAP_V1 (P0 commercial)
 * - bounded retries
 * - deterministic empty state with reason
 * - no noisy "give up after 20 tries"
 */
(function(){
  'use strict';

  // prevent double init (old V2 flag might exist; keep compatibility)
  if (window.__VSP_CHARTS_BOOT_SAFE_V3) return;
  window.__VSP_CHARTS_BOOT_SAFE_V3 = true;

  const TAG = 'VSP_CHARTS_BOOT_SAFE_V3';
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

  function nowISO(){
    try { return new Date().toISOString(); } catch(_) { return ''; }
  }

  function esc(s){
    return String(s ?? '')
      .replaceAll('&','&amp;')
      .replaceAll('<','&lt;')
      .replaceAll('>','&gt;')
      .replaceAll('"','&quot;')
      .replaceAll("'","&#039;");
  }

  function pickMount(){
    for (const s of SELS){
      const el = document.querySelector(s);
      if (el) return el;
    }
    // fallback: any element that looks like charts zone
    const any = document.querySelector('.chart, .charts, .vsp-chart, .vsp-charts');
    return any || null;
  }

  function ensureStyles(){
    if (document.getElementById('vsp-charts-empty-style-v1')) return;
    const st = document.createElement('style');
    st.id = 'vsp-charts-empty-style-v1';
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
    if (!mount) {
      if (!warnedOnce){
        warnedOnce = true;
        console.warn(`[${TAG}] empty-state: missing chart container; reason=`, reason);
      }
      return;
    }

    const html = `
      <div class="vsp-charts-empty" data-vsp-charts-empty="1">
        <div class="vsp-charts-empty-hd">
          <div class="vsp-charts-empty-title">Charts</div>
          <div class="vsp-charts-empty-pill">WAITING</div>
        </div>
        <div class="vsp-charts-empty-sub">
          <div class="vsp-charts-empty-reason">${esc(reason || 'waiting for run data')}</div>
          <div>Updated: ${esc(nowISO())}</div>
        </div>
        <button class="vsp-charts-empty-btn" type="button" id="vspChartsRetryBtn">Retry charts</button>
      </div>
    `;

    // Do NOT wipe real charts if already rendered
    const already = mount.querySelector('[data-vsp-charts-empty="1"]');
    if (already) {
      already.querySelector('.vsp-charts-empty-reason').textContent = reason || 'waiting for run data';
    } else {
      // insert at top without destroying existing nodes
      const wrapper = document.createElement('div');
      wrapper.innerHTML = html;
      mount.prepend(wrapper.firstElementChild);
    }

    const btn = mount.querySelector('#vspChartsRetryBtn');
    if (btn && !btn.__bound){
      btn.__bound = true;
      btn.addEventListener('click', function(){
        tries = 0;
        locked = false;
        scheduleTry('manual retry');
      });
    }
  }

  function clearEmptyState(){
    const mount = pickMount();
    if (!mount) return;
    const el = mount.querySelector('[data-vsp-charts-empty="1"]');
    if (el) el.remove();
  }

  function pickEngine(){
    // prefer V3
    if (window.VSP_CHARTS_ENGINE_V3 && typeof window.VSP_CHARTS_ENGINE_V3.initAll === 'function'){
      return { tag:'VSP_CHARTS_ENGINE_V3', eng: window.VSP_CHARTS_ENGINE_V3 };
    }
    // fallback common names
    if (window.VSP_CHARTS_ENGINE && typeof window.VSP_CHARTS_ENGINE.initAll === 'function'){
      return { tag:'VSP_CHARTS_ENGINE', eng: window.VSP_CHARTS_ENGINE };
    }
    if (typeof window.vspChartsInitAll === 'function'){
      return { tag:'window.vspChartsInitAll', eng: { initAll: window.vspChartsInitAll } };
    }
    return null;
  }

  function computeDelay(n){
    // small bounded backoff
    return Math.min(1200, BASE_DELAY_MS + (n * 120));
  }

  async function tryInit(reasonTag){
    if (locked) return;
    locked = true;

    tries += 1;

    const mount = pickMount();
    if (!mount){
      lastReason = 'missing chart container';
      locked = false;
      return false;
    }

    const pe = pickEngine();
    if (!pe){
      lastReason = 'charts module not loaded (engine missing)';
      locked = false;
      return false;
    }

    try{
      // some engines accept a tag
      pe.eng.initAll(reasonTag || TAG);
      clearEmptyState();
      console.log(`[${TAG}] initAll OK via`, pe.tag, 'tries=', tries);
      return true;
    }catch(e){
      lastReason = `initAll failed: ${e && e.message ? e.message : String(e)}`;
      if (!warnedOnce){
        warnedOnce = true;
        console.warn(`[${TAG}] initAll failed (will retry bounded)`, e);
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
        // final: stable empty state (commercial)
        renderEmptyState(lastReason || `no chart data (tries=${tries}/${MAX_TRIES})`);
        console.log(`[${TAG}] done: empty-state shown; tries=${tries}/${MAX_TRIES}; reason=`, lastReason);
        return;
      }

      renderEmptyState(lastReason || `waiting for chart data (tries=${tries}/${MAX_TRIES})`);
      scheduleTry(tag);
    }, delay);
  }

  function boot(){
    tries = 0;
    locked = false;
    lastReason = '';
    warnedOnce = false;
    scheduleTry('boot');
  }

  // public hook
  window.VSP_CHARTS_BOOT_SAFE_V3 = {
    boot,
    refresh: () => scheduleTry('refresh')
  };

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', boot, { once:true });
  } else {
    boot();
  }

  // optional: if your UI dispatches run change events, charts refresh will be responsive
  window.addEventListener('vsp:rid_changed', () => scheduleTry('rid_changed'));
})();
JS

node --check "$F" >/dev/null && echo "[OK] node --check"
echo "[OK] patched charts bootstrap => $F"
echo "[NEXT] restart UI + hard refresh (Ctrl+Shift+R)"
