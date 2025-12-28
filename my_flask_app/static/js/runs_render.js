(function () {
  if (!window.VSP) window.VSP = {};

  function renderRuns(rows) {
    var tbody = document.querySelector('#tbl-runs tbody');
    if (!tbody) return;
    tbody.innerHTML = '';

    (rows || []).forEach(function (r) {
      var tr = document.createElement('tr');

      var runId = r.run_id || r.id || '';
      var ts = r.ts || r.time || r.timestamp || '';
      var profile = r.profile || '-';
      var source = r.source_path || r.src || '-';
      var findings = r.findings_total || r.total_findings || r.total || 0;
      var status = r.status || 'UNKNOWN';
      var reports = r.reports || {};

      tr.innerHTML =
        '<td>' + runId + '</td>' +
        '<td>' + ts + '</td>' +
        '<td>' + profile + '</td>' +
        '<td>' + source + '</td>' +
        '<td>' + findings + '</td>' +
        '<td>' + status + '</td>' +
        '<td class="runs-reports-cell"></td>';

      var cellReports = tr.querySelector('.runs-reports-cell');

      function addLink(label, urlKey) {
        var url = reports[urlKey];
        if (!url) return;
        var a = document.createElement('a');
        a.href = url;
        a.target = '_blank';
        a.textContent = label;
        a.className = 'run-report-link';
        cellReports.appendChild(a);
      }

      addLink('HTML', 'html');
      addLink('PDF', 'pdf');
      addLink('CSV', 'csv');
      addLink('SBOM', 'sbom');

      tbody.appendChild(tr);
    });
  }

  function applyFilters(allRows) {
    var profileSel = document.getElementById('run-filter-profile');
    var statusSel = document.getElementById('run-filter-status');
    var searchInput = document.getElementById('run-search');

    var profileVal = profileSel ? (profileSel.value || '') : '';
    var statusVal = statusSel ? (statusSel.value || '') : '';
    var searchVal = searchInput ? (searchInput.value || '').toLowerCase() : '';

    var filtered = (allRows || []).filter(function (r) {
      var ok = true;
      if (profileVal && profileVal !== 'ALL') {
        ok = ok && (r.profile === profileVal);
      }
      if (statusVal && statusVal !== 'ALL') {
        ok = ok && (r.status === statusVal);
      }
      if (searchVal) {
        var txt = JSON.stringify(r).toLowerCase();
        ok = ok && txt.indexOf(searchVal) !== -1;
      }
      return ok;
    });

    renderRuns(filtered);
  }

  function initFilters(allRows) {
    var profileSel = document.getElementById('run-filter-profile');
    var statusSel = document.getElementById('run-filter-status');
    var searchInput = document.getElementById('run-search');

    if (profileSel) {
      var profiles = Array.from(new Set((allRows || []).map(r => r.profile).filter(Boolean)));
      profileSel.innerHTML = '<option value="ALL">All profiles</option>' +
        profiles.map(p => `<option value="${p}">${p}</option>`).join('');
      profileSel.onchange = function () { applyFilters(allRows); };
    }

    if (statusSel) {
      var statuses = Array.from(new Set((allRows || []).map(r => r.status).filter(Boolean)));
      statusSel.innerHTML = '<option value="ALL">All status</option>' +
        statuses.map(s => `<option value="${s}">${s}</option>`).join('');
      statusSel.onchange = function () { applyFilters(allRows); };
    }

    if (searchInput) {
      searchInput.oninput = function () { applyFilters(allRows); };
    }
  }

  window.VSP.initRuns = async function () {
    console.log('[VSP][UI] initRuns');
    var rows = await window.VSP.API.getRunsIndex();
    if (!Array.isArray(rows)) {
      console.warn('[VSP][UI] runs_index_v3 không phải array');
      rows = [];
    }
    initFilters(rows);
    applyFilters(rows);
  };
})();
