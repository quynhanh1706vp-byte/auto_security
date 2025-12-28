(function () {
  function selectTab(tabName) {
    const tabs = document.querySelectorAll('.tab');
    tabs.forEach(t => {
      t.classList.toggle('active', t.id === 'tab-' + tabName);
    });

    const items = document.querySelectorAll('#vsp-sidebar .menu li');
    items.forEach(li => {
      li.classList.toggle('active', li.getAttribute('data-tab') === tabName);
    });

    const headerTitle = document.getElementById('vsp-header-title');
    const subtitle = document.getElementById('vsp-header-subtitle');
    if (headerTitle) {
      if (tabName === 'dashboard') {
        headerTitle.textContent = 'Dashboard';
        subtitle.textContent = 'CIO-Level Security Overview';
        if (window.VSP && typeof window.VSP.initDashboard === 'function') {
          window.VSP.initDashboard();
        }
      } else if (tabName === 'runs') {
        headerTitle.textContent = 'Runs & Reports';
        subtitle.textContent = 'History of scans and reports';
        if (window.VSP && typeof window.VSP.initRuns === 'function') {
          window.VSP.initRuns();
        }
      } else if (tabName === 'datasource') {
        headerTitle.textContent = 'Data Source';
        subtitle.textContent = 'Unified findings from all tools';
        if (window.VSP && typeof window.VSP.initDatasource === 'function') {
          window.VSP.initDatasource();
        }
      } else if (tabName === 'settings') {
        headerTitle.textContent = 'Settings';
        subtitle.textContent = 'Profiles, sources, tools & integrations';
        if (window.VSP && typeof window.VSP.initSettings === 'function') {
          window.VSP.initSettings();
        }
      } else if (tabName === 'overrides') {
        headerTitle.textContent = 'Rule Overrides';
        subtitle.textContent = 'Noise reduction & severity tuning';
        if (window.VSP && typeof window.VSP.initOverrides === 'function') {
          window.VSP.initOverrides();
        }
      }
    }

    try {
      const newHash = '#tab=' + tabName;
      if (window.location.hash !== newHash) {
        history.replaceState(null, '', newHash);
      }
    } catch (e) {}
  }

  function initSidebar() {
    const items = document.querySelectorAll('#vsp-sidebar .menu li');
    items.forEach(li => {
      li.addEventListener('click', () => {
        const tabName = li.getAttribute('data-tab');
        selectTab(tabName);
      });
    });
  }

  function initialTabFromHash() {
    const h = window.location.hash || '';
    const m = h.match(/tab=([a-zA-Z0-9_-]+)/);
    if (m && m[1]) {
      return m[1];
    }
    return 'dashboard';
  }

  window.addEventListener('DOMContentLoaded', () => {
    if (!window.VSP) window.VSP = {};
    initSidebar();
    const t = initialTabFromHash();
    selectTab(t);

    const btn = document.getElementById('btn-global-refresh');
    if (btn) {
      btn.addEventListener('click', () => {
        const active = document.querySelector('.tab.active');
        if (!active) return;
        const id = active.id.replace('tab-', '');
        selectTab(id);
      });
    }
  });
})();
