(function () {
  if (!window.VSP) window.VSP = {};

  function setKpi(id, label, value, sub) {
    var el = document.getElementById(id);
    if (!el) return;
    el.innerHTML = `
      <div class="kpi-label">${label}</div>
      <div class="kpi-value">${value != null ? value : '-'}</div>
      <div class="kpi-sub">${sub || ''}</div>
    `;
  }

  function fillTopTable(tableId, rows, columns) {
    var el = document.getElementById(tableId);
    if (!el) return;

    var thead = '<thead><tr>' +
      columns.map(c => `<th>${c.label}</th>`).join('') +
      '</tr></thead>';

    var bodyRows = (rows || []).map(r => {
      return '<tr>' + columns.map(c => {
        var v = r[c.key];
        if (v == null) v = '';
        return `<td>${v}</td>`;
      }).join('') + '</tr>';
    }).join('');

    el.innerHTML = thead + '<tbody>' + bodyRows + '</tbody>';
  }

  window.VSP.initDashboard = async function () {
    console.log('[VSP][UI] initDashboard');

    // gọi song song 2 API
    var dashPromise = window.VSP.API.getDashboard();
    var dsDashPromise = window.VSP.API.getDashboardDatasource();

    var dash = await dashPromise;
    var dsDash = await dsDashPromise;

    if (!dash) {
      console.warn('[VSP][UI] /api/vsp/dashboard trả null hoặc lỗi');
      setKpi('kpi-total', 'Total Findings', 'N/A', 'No dashboard data');
      return;
    }

    // ----- KPI -----
    // cố gắng bắt các field phổ biến + fallback
    var total =
      dash.total_findings ||
      dash.total ||
      (dash.count && dash.count.total) ||
      0;

    var sev = dash.severity || dash.severity_counts || dash.buckets || {};
    var byTool = dash.by_tool || dash.tools || {};

    var score = dash.security_score || dash.score || null;
    var topTool = dash.top_tool || dash.riskiest_tool || null;
    var topCwe = dash.top_cwe || null;
    var topModule = dash.top_module || dash.riskiest_module || null;

    setKpi('kpi-total', 'Total Findings', total, '');
    setKpi('kpi-critical', 'Critical', sev.CRITICAL || sev.critical || 0, '');
    setKpi('kpi-high', 'High', sev.HIGH || sev.high || 0, '');
    setKpi('kpi-medium', 'Medium', sev.MEDIUM || sev.medium || 0, '');
    setKpi('kpi-low', 'Low', sev.LOW || sev.low || 0, '');
    var infoTrace = (sev.INFO || sev.info || 0) + (sev.TRACE || sev.trace || 0);
    setKpi('kpi-infotrace', 'Info / Trace', infoTrace, '');

    setKpi('kpi-score', 'Security Score', score != null ? score : '-', '/100');
    setKpi('kpi-tool', 'Top Risky Tool', topTool || '-', '');
    setKpi('kpi-cwe', 'Top CWE', topCwe || '-', '');
    setKpi('kpi-module', 'Top Module', topModule || '-', '');

    // ----- TOP TABLES -----
    // ưu tiên dùng dsDash nếu BE đã tính sẵn; nếu không, dùng dash.top_*
    var topFindings = (dsDash && dsDash.top_findings) || dash.top_findings || [];
    var topCves = (dsDash && dsDash.top_cve) || dash.top_cve || [];
    var topModules = (dsDash && dsDash.top_modules) || dash.top_modules || [];

    // nếu topFindings còn rỗng nhưng dsDash có raw_findings -> lấy vài dòng làm mẫu
    if ((!topFindings || !topFindings.length) && dsDash && dsDash.findings_sample) {
      topFindings = dsDash.findings_sample.slice(0, 5);
    }

    fillTopTable('top-findings', topFindings, [
      { key: 'severity', label: 'Sev' },
      { key: 'tool', label: 'Tool' },
      { key: 'rule_id', label: 'Rule' },
      { key: 'file', label: 'File' },
      { key: 'message', label: 'Message' }
    ]);

    fillTopTable('top-cve', topCves, [
      { key: 'cve', label: 'CVE' },
      { key: 'count', label: 'Count' },
      { key: 'max_severity', label: 'Max Sev' }
    ]);

    fillTopTable('top-mod', topModules, [
      { key: 'module', label: 'Module / Package' },
      { key: 'count', label: 'Findings' },
      { key: 'critical', label: 'Critical/High' }
    ]);

    console.log('[VSP][UI] Dashboard filled from API');
  };
})();
