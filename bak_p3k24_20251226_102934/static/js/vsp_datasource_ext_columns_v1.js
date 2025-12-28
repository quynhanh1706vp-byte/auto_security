(function () {
  const BASE_URL = '/api/vsp/datasource_v2';
  const INIT_DELAY_MS = 1200;

  function fmtInt(n) {
    if (n == null || isNaN(n)) return '-';
    return Number(n).toLocaleString('en-US');
  }

  function esc(s) {
    if (s == null) return '';
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  function getSeverity(f) {
    return (f.severity || f.raw_severity || '').toUpperCase() || 'INFO';
  }

  function buildRow(f) {
    const sev = getSeverity(f);
    const tool = f.tool || f.source || '-';
    const cwe = f.cwe || f.cwe_id || f.rule_id || '-';
    const modulePath = f.module || f.file || f.path || f.location || '-';
    const message = f.message || f.title || f.short_message || '-';
    const runId = f.run_id || '-';

    return `
      <tr>
        <td><span class="vsp-badge vsp-badge-sev vsp-sev-${sev.toLowerCase()}">${sev}</span></td>
        <td>${esc(tool)}</td>
        <td>${esc(cwe)}</td>
        <td class="vsp-mono">${esc(modulePath)}</td>
        <td>${esc(message)}</td>
        <td class="vsp-mono">${esc(runId)}</td>
      </tr>
    `;
  }

  function renderSkeleton(tab) {
    tab.innerHTML = `
      <div class="vsp-tab-inner vsp-tab-datasource">
        <div class="vsp-tab-header">
          <h2>Data Source</h2>
          <p class="vsp-tab-subtitle">
            Nguồn dữ liệu chi tiết của tất cả findings sau khi unify. Có thể lọc theo severity, tool, CWE.
          </p>
        </div>

        <div class="vsp-filter-row">
          <select id="vsp-ds-filter-sev" class="vsp-input">
            <option value="">Severity: All</option>
            <option value="CRITICAL">Critical</option>
            <option value="HIGH">High</option>
            <option value="MEDIUM">Medium</option>
            <option value="LOW">Low</option>
            <option value="INFO">Info</option>
            <option value="TRACE">Trace</option>
          </select>

          <input id="vsp-ds-filter-tool" class="vsp-input" placeholder="Tool (semgrep, kics,…)" />

          <input id="vsp-ds-filter-cwe" class="vsp-input" placeholder="CWE / Rule ID" />

          <input id="vsp-ds-filter-text" class="vsp-input vsp-flex" placeholder="Search message / path…" />

          <button id="vsp-ds-refresh" class="vsp-btn vsp-btn-secondary">Reload</button>
          <button id="vsp-ds-export-json" class="vsp-btn vsp-btn-ghost">Export JSON</button>
        </div>

        <div class="vsp-card vsp-table-card">
          <div class="vsp-table-header">
            <div>
              <h3>Findings table</h3>
              <p class="vsp-table-subtitle">
                Tối đa 200 bản ghi mới nhất theo filter. Dùng để drill-down nhanh trước khi mở báo cáo chi tiết.
              </p>
            </div>
            <div class="vsp-table-kpi">
              <span id="vsp-ds-kpi-total">0</span> records
            </div>
          </div>

          <div class="vsp-table-wrapper">
            <table class="vsp-table" id="vsp-ds-table">
              <thead>
                <tr>
                  <th>Severity</th>
                  <th>Tool</th>
                  <th>CWE / Rule</th>
                  <th>Module / Path</th>
                  <th>Message</th>
                  <th>Run</th>
                </tr>
              </thead>
              <tbody>
                <tr><td colspan="6" class="vsp-table-loading">Đang tải dữ liệu findings…</td></tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    `;
  }

  async function bindDatasource(tab) {
    renderSkeleton(tab);

    const selSev = tab.querySelector('#vsp-ds-filter-sev');
    const inpTool = tab.querySelector('#vsp-ds-filter-tool');
    const inpCwe = tab.querySelector('#vsp-ds-filter-cwe');
    const inpText = tab.querySelector('#vsp-ds-filter-text');
    const btnReload = tab.querySelector('#vsp-ds-refresh');
    const btnExportJson = tab.querySelector('#vsp-ds-export-json');
    const tbody = tab.querySelector('#vsp-ds-table tbody');
    const kpiTotal = tab.querySelector('#vsp-ds-kpi-total');

    async function fetchAndRender() {
      if (!tbody) return;
      tbody.innerHTML = `<tr><td colspan="6" class="vsp-table-loading">Đang tải dữ liệu findings…</td></tr>`;

      const params = new URLSearchParams();
      params.set('limit', '200');
      if (selSev && selSev.value) params.set('severity', selSev.value);
      if (inpTool && inpTool.value.trim()) params.set('tool', inpTool.value.trim());
      if (inpCwe && inpCwe.value.trim()) params.set('cwe', inpCwe.value.trim());
      if (inpText && inpText.value.trim()) params.set('q', inpText.value.trim());

      let data;
      try {
        const res = await fetch(`${BASE_URL}?${params.toString()}`, { cache: 'no-store' });
        data = await res.json();
      } catch (e) {
        console.error('[VSP_DS_TAB] Failed to load datasource_v2', e);
        tbody.innerHTML = `<tr><td colspan="6" class="vsp-table-error">
          Không tải được dữ liệu Data Source từ API.
        </td></tr>`;
        if (kpiTotal) kpiTotal.textContent = '0';
        return;
      }

      const items = Array.isArray(data.items) ? data.items : Array.isArray(data) ? data : [];
      if (kpiTotal) kpiTotal.textContent = fmtInt(items.length);

      if (!items.length) {
        tbody.innerHTML = `<tr><td colspan="6" class="vsp-table-empty">
          Không có bản ghi nào phù hợp với filter hiện tại.
        </td></tr>`;
        return;
      }

      tbody.innerHTML = items.map(buildRow).join('');
      console.log('[VSP_DS_TAB] Rendered Data Source with', items.length, 'items');
    }

    if (btnReload) {
      btnReload.addEventListener('click', () => {
        fetchAndRender();
      });
    }

    if (btnExportJson) {
      btnExportJson.addEventListener('click', () => {
        const params = new URLSearchParams();
        params.set('limit', '2000');
        if (selSev && selSev.value) params.set('severity', selSev.value);
        if (inpTool && inpTool.value.trim()) params.set('tool', inpTool.value.trim());
        if (inpCwe && inpCwe.value.trim()) params.set('cwe', inpCwe.value.trim());
        if (inpText && inpText.value.trim()) params.set('q', inpText.value.trim());

        const url = `${BASE_URL}?${params.toString()}`;
        window.open(url, '_blank');
      });
    }

    [inpTool, inpCwe, inpText].forEach(inp => {
      if (!inp) return;
      inp.addEventListener('keydown', e => {
        if (e.key === 'Enter') {
          e.preventDefault();
          fetchAndRender();
        }
      });
    });

    fetchAndRender();
  }

  let initialized = false;

  function tryInit() {
    if (initialized) return;
    const tab = document.querySelector('#vsp-tab-datasource');
    if (!tab) {
      setTimeout(tryInit, 500);
      return;
    }
    initialized = true;
    setTimeout(() => bindDatasource(tab), INIT_DELAY_MS);
  }

  tryInit();
})();
