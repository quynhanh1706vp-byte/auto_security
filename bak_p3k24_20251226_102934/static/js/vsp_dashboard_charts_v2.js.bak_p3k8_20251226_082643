// VSP_DASHBOARD_CHARTS_V2_STUB
// Legacy charts_v2 đã được thay bằng pretty_v3.

(function () {
  console.log('[VSP_CHARTS_V2_STUB] legacy charts_v2 replaced by pretty_v3');

  function forwardToV3(dashboard) {
    if (window.VSP_DASHBOARD_CHARTS_V3 &&
        typeof window.VSP_DASHBOARD_CHARTS_V3.updateFromDashboard === 'function') {
      try {
        window.VSP_DASHBOARD_CHARTS_V3.updateFromDashboard(dashboard);
      } catch (e) {
        console.error('[VSP_CHARTS_V2_STUB] error in V3 charts', e);
      }
    } else {
      console.warn('[VSP_CHARTS_V2_STUB] V3 charts chưa sẵn, skip.');
    }
  }

  // Global API mà vsp_dashboard_enhance_v1.js dùng
  window.VSP_DASHBOARD_CHARTS = window.VSP_DASHBOARD_CHARTS || {};
  window.VSP_DASHBOARD_CHARTS.updateFromDashboard = forwardToV3;
  window.vspDashboardChartsUpdateFromDashboard = forwardToV3;
})();
