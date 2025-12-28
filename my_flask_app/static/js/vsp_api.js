(function () {
  const API = {
    getDashboard() {
      return fetch('/api/vsp/dashboard_v3')
        .then(r => r.json())
        .catch(err => {
          console.warn('[VSP][API] dashboard error', err);
          return null;
        });
    },
    getDashboardDatasource() {
      return fetch('/api/vsp/datasource?mode=dashboard')
        .then(r => r.json())
        .catch(err => {
          console.warn('[VSP][API] datasource?mode=dashboard error', err);
          return null;
        });
    },
    getRunsIndex() {
      return fetch('/api/vsp/runs_index_v3')
        .then(r => r.json())
        .catch(err => {
          console.warn('[VSP][API] runs_index_v3 error', err);
          return [];
        });
    },
    getDatasource() {
      return fetch('/api/vsp/datasource')
        .then(r => r.json())
        .catch(err => {
          console.warn('[VSP][API] datasource error', err);
          return [];
        });
    },
    getSettings() {
      return fetch('/api/vsp/settings')
        .then(r => r.json())
        .catch(err => {
          console.warn('[VSP][API] settings error', err);
          return null;
        });
    },
    getRuleOverrides() {
      return fetch('/api/vsp/rule_overrides')
        .then(r => r.json())
        .catch(err => {
          console.warn('[VSP][API] rule_overrides error', err);
          return [];
        });
    }
  };

  if (!window.VSP) window.VSP = {};
  window.VSP.API = API;
})();
