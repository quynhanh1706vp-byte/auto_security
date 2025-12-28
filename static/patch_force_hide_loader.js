(function () {
  console.log('[PATCH] patch_force_hide_loader.js loaded');

  function nukeOverlay() {
    try {
      var body = document.body;
      if (body && body.classList) {
        body.classList.remove('sb-loading', 'loading');
        body.style.overflow = 'auto';
      }

      var selectors = [
        '#sb-loading-overlay',
        '.sb-loading-overlay',
        '#loadingOverlay',
        '.loading-overlay'
      ];

      selectors.forEach(function (sel) {
        var els = document.querySelectorAll(sel);
        if (!els) return;
        els.forEach(function (el) {
          el.style.opacity = '0';
          el.style.display = 'none';
          el.style.visibility = 'hidden';
          el.style.pointerEvents = 'none';
          el.style.zIndex = '-1';
        });
      });

      console.log('[PATCH] overlay removed (if existed)');
    } catch (e) {
      console.log('[PATCH] error while removing overlay', e);
    }
  }

  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    setTimeout(nukeOverlay, 800);
  } else {
    window.addEventListener('load', function () {
      setTimeout(nukeOverlay, 800);
    });
  }
})();
