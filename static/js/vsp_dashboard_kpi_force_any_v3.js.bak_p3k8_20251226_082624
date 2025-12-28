(function () {
  if (window.VSP_DASH_FORCE_V3_INIT) {
    console.log('[VSP_DASH_FORCE] already initialized, skip');
    return;
  }
  window.VSP_DASH_FORCE_V3_INIT = true;

  console.log('[VSP_DASH_FORCE] vsp_dashboard_kpi_force_any_v3.js loaded');

  function fmtInt(n) {
    if (n == null || isNaN(n)) return '--';
    return Number(n).toLocaleString('en-US');
  }

  function setText(id, value, isNumber) {
    var el = document.getElementById(id);
    if (!el) return;
    if (value == null || value === '') {
      el.textContent = '--';
      return;
    }
    el.textContent = isNumber ? fmtInt(value) : String(value);
  }

  async function loadKpiOnce() {
    try {
      const res = await fetch('/api/vsp/dashboard_v3');
      if (!res.ok) {
        console.warn('[VSP_DASH_FORCE] dashboard_v3 HTTP != 200', res.status);
        return;
      }
      const data = await res.json();
      const sev = data.by_severity || data.severity_cards || {};

      let topTool   = data.top_risky_tool;
      let topCwe    = data.top_impacted_cwe;
      let topModule = data.top_vulnerable_module;

      if (topCwe && typeof topCwe === 'object') {
        topCwe =
          topCwe.cwe_id ||
          topCwe.cwe ||
          topCwe.id ||
          topCwe.name ||
          JSON.stringify(topCwe);
      }
      if (topModule && typeof topModule === 'object') {
        topModule =
          topModule.path ||
          topModule.module ||
          topModule.id ||
          topModule.name ||
          JSON.stringify(topModule);
      }

      // 5 KPI chính – ĐÚNG ID HTML ANH ĐANG CÓ
      setText('vsp-kpi-total',          data.total_findings, true);
      setText('vsp-kpi-security-score', data.security_posture_score, true);
      setText('vsp-kpi-top-tool',       topTool, false);
      setText('vsp-kpi-top-cwe',        topCwe, false);
      setText('vsp-kpi-top-module',     topModule, false);

      // 6 severity – ĐÚNG ID HTML
      setText('vsp-kpi-critical', sev.CRITICAL || 0, true);
      setText('vsp-kpi-high',     sev.HIGH     || 0, true);
      setText('vsp-kpi-medium',   sev.MEDIUM   || 0, true);
      setText('vsp-kpi-low',      sev.LOW      || 0, true);
      setText('vsp-kpi-info',     sev.INFO     || 0, true);
      setText('vsp-kpi-trace',    sev.TRACE    || 0, true);

      console.log('[VSP_DASH_FORCE] KPI applied', {
        total: data.total_findings,
        score: data.security_posture_score,
        topTool,
        topCwe,
        topModule,
        by_severity: sev
      });
    } catch (e) {
      console.error('[VSP_DASH_FORCE] Error loading KPI', e);
    }
  }

  function init() {
    var tries = 0;
    var t = setInterval(function () {
      var pane = document.getElementById('vsp-dashboard-main');
      if (pane) {
        clearInterval(t);
        loadKpiOnce();
      } else if (tries++ > 20) {
        clearInterval(t);
        console.warn('[VSP_DASH_FORCE] Hết retries, không thấy #vsp-dashboard-main');
      }
    }, 500);
  }

  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    init();
  } else {
    document.addEventListener('DOMContentLoaded', init);
  }
})();
