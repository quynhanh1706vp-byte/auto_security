/* VSP_P0_CIO_SCRUB_NA_ALL_V1P4C */

function vspNormalizeTopModule(m) {
  if (!m) return '0';
  if (typeof m === 'string') return m;
  try {
    if (m.label) return String(m.label);
    if (m.path) return String(m.path);
    if (m.id)   return String(m.id);
    return String(m);
  } catch (e) {
    return '0';
  }
}

'use strict';

(function () {
  const LOG = '[VSP_DASHBOARD_KPI]';

  function setText(id, value) {
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = value;
  }

  function renderKpi(model) {
    if (!model) return;
    const sev =
      model.severity_cards ||
      model.summary_by_severity ||
      model.summary_all ||
      {};

    const total =
      model.total_findings ??
      model.total ??
      sev.TOTAL ??
      0;

    setText('vsp-kpi-total', total);
    setText('vsp-kpi-critical', sev.CRITICAL ?? 0);
    setText('vsp-kpi-high', sev.HIGH ?? 0);
    setText('vsp-kpi-medium', sev.MEDIUM ?? 0);
    setText('vsp-kpi-low', sev.LOW ?? 0);
    setText('vsp-kpi-info', (sev.INFO ?? 0) + (sev.TRACE ?? 0));

    if (model.security_posture_score != null) {
      setText('vsp-kpi-score-main', model.security_posture_score + '/100');
    }

    if (model.top_risky_tool) {
      setText('vsp-kpi-top-tool', model.top_risky_tool);
    }
    if (model.top_impacted_cwe) {
      setText('vsp-kpi-top-cwe', model.top_impacted_cwe);
    }
    if (model.top_vulnerable_module) {
      setText('vsp-kpi-top-module', model.top_vulnerable_module);
    }

    if (model.latest_run_id) {
      setText('vsp-last-run-span', model.latest_run_id);
    }

    // Cho Charts JS dùng chung model này
    window.VSP_DASHBOARD_MODEL = model;
    if (typeof window.vspRenderChartsFromDashboard === 'function') {
      try {
        window.vspRenderChartsFromDashboard(model);
      } catch (e) {
        console.error(LOG, 'Chart render error', e);
      }
    }
  }

  async function loadDashboard() {
    const url = '/api/vsp/dashboard_v3';
    console.log(LOG, 'Loading', url);

    try {
      const res = await fetch(url, { credentials: 'same-origin' });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const data = await res.json();
      console.log(LOG, 'Dashboard model:', data);
      renderKpi(data);
    } catch (err) {
      console.error(LOG, 'Load dashboard error:', err);
      const errBox = document.getElementById('vsp-dashboard-error');
      if (errBox) {
        errBox.textContent = 'Không tải được dashboard: ' + (err.message || err);
        errBox.style.display = 'block';
      }
    }
  }

  document.addEventListener('DOMContentLoaded', loadDashboard);
})();
