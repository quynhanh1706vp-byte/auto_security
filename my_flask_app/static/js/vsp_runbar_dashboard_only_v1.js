/* ===== VSP RUN BAR – DASHBOARD ONLY (offsetHeight guard) ===== */
(function () {
  function toggleRunBarVisibility() {
    var bar = document.getElementById('vsp-run-bar');
    var cfg = document.getElementById('vsp-settings-config-block');
    if (!bar && !cfg) return;

    var dash = document.getElementById('tab-dashboard');
    var show = true;

    if (dash) {
      var style = window.getComputedStyle(dash);
      // Nếu tab-dashboard đang display:none hoặc ẩn thì coi như không active
      var visible =
        style.display !== 'none' &&
        style.visibility !== 'hidden' &&
        dash.offsetHeight > 0 &&
        dash.offsetWidth > 0;

      show = visible;
    }

    if (bar) {
      bar.style.display = show ? '' : 'none';
    }
    if (cfg) {
      cfg.style.display = show ? '' : 'none';
    }
  }

  function init() {
    console.log('[VSP][RUNBAR] dashboard-only guard init');
    toggleRunBarVisibility();
    // Poll mỗi 300ms để bắt kịp khi user đổi tab
    setInterval(toggleRunBarVisibility, 300);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
