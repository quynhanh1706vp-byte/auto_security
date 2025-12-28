(function () {
  if (!window.VSP) window.VSP = {};

  const STATE = {
    runs: [],
    filtered: [],
    selectedRunId: null,
    filters: {
      profile: 'ALL',
      text: ''
    }
  };

  function injectRunsStyles() {
    if (document.getElementById('vsp-runs-style')) return;
    const css = `
      #tab-runs {
        padding: 16px 20px;
        color: #e5e7eb;
        font-family: system-ui, -apple-system, BlinkMacSystemFont, "Inter", sans-serif;
      }
      .vsp-runs-root {
        display: flex;
        flex-direction: column;
        gap: 16px;
      }
      .vsp-runs-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
      }
      .vsp-runs-title-main {
        font-size: 20px;
        font-weight: 600;
        color: #f9fafb;
      }
      .vsp-runs-title-sub {
        font-size: 13px;
        color: #9ca3af;
      }
      .vsp-runs-actions {
        display: flex;
        align-items: center;
        gap: 8px;
      }
      .vsp-btn {
        padding: 6px 12px;
        border-radius: 999px;
        border: 1px solid #4b5563;
        background: #111827;
        color: #e5e7eb;
        font-size: 12px;
        cursor: pointer;
        display: inline-flex;
        align-items: center;
        gap: 6px;
      }
      .vsp-btn:hover {
        border-color: #6b7280;
        background: #020617;
      }
      .vsp-runs-filters {
        display: flex;
        flex-wrap: wrap;
        gap: 12px;
        padding: 10px 12px;
        border-radius: 10px;
        background: radial-gradient(circle at top left, rgba(59,130,246,0.15), transparent 55%),
                    radial-gradient(circle at bottom right, rgba(147,51,234,0.18), transparent 55%),
                    #020617;
        border: 1px solid rgba(31,41,55,0.9);
      }
      .vsp-runs-filter-item {
        display: flex;
        flex-direction: column;
        gap: 4px;
        font-size: 11px;
        color: #9ca3af;
      }
      .vsp-runs-filter-item label {
        font-weight: 500;
      }
      .vsp-runs-filter-item select,
      .vsp-runs-filter-item input {
        min-width: 160px;
        padding: 6px 10px;
        border-radius: 7px;
        border: 1px solid #4b5563;
        background: #020617;
        color: #e5e7eb;
        font-size: 12px;
        outline: none;
      }
      .vsp-runs-filter-item input::placeholder {
        color: #6b7280;
      }
      .vsp-runs-main {
        display: grid;
        grid-template-columns: minmax(0, 2.1fr) minmax(0, 1.4fr);
        gap: 16px;
        min-height: 360px;
      }
      @media (max-width: 1200px) {
        .vsp-runs-main {
          grid-template-columns: minmax(0, 1fr);
        }
      }
      .vsp-card {
        border-radius: 12px;
        background: #020617;
        border: 1px solid rgba(31,41,55,0.9);
        box-shadow: 0 16px 40px rgba(0,0,0,0.7);
        padding: 12px 14px;
        display: flex;
        flex-direction: column;
        gap: 8px;
      }
      .vsp-card-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        gap: 8px;
      }
      .vsp-card-title {
        font-size: 13px;
        font-weight: 600;
        color: #e5e7eb;
      }
      .vsp-card-sub {
        font-size: 11px;
        color: #6b7280;
      }
      .vsp-tag {
        display: inline-flex;
        align-items: center;
        border-radius: 999px;
        padding: 2px 8px;
        font-size: 11px;
        border: 1px solid #374151;
        color: #9ca3af;
        gap: 4px;
      }
      .vsp-tag-dot {
        width: 6px;
        height: 6px;
        border-radius: 999px;
        background: #22c55e;
      }
      .vsp-table-wrap {
        overflow: auto;
        border-radius: 10px;
        border: 1px solid #111827;
      }
      table.vsp-table {
        width: 100%;
        border-collapse: collapse;
        font-size: 11px;
      }
      table.vsp-table thead {
        background: rgba(15,23,42,0.95);
      }
      table.vsp-table th,
      table.vsp-table td {
        padding: 6px 8px;
        white-space: nowrap;
        border-bottom: 1px solid #020617;
      }
      table.vsp-table th {
        text-align: left;
        font-weight: 500;
        color: #9ca3af;
        position: sticky;
        top: 0;
        z-index: 1;
      }
      table.vsp-table tbody tr {
        cursor: pointer;
        background: #020617;
      }
      table.vsp-table tbody tr:nth-child(even) {
        background: #020617;
      }
      table.vsp-table tbody tr:hover {
        background: radial-gradient(circle at left, rgba(59,130,246,0.24), transparent 55%);
      }
      table.vsp-table tbody tr.vsp-row-selected {
        background: radial-gradient(circle at left, rgba(147,51,234,0.3), transparent 60%);
      }
      .vsp-mono {
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
      }
      .vsp-status-pill {
        display: inline-flex;
        align-items: center;
        padding: 1px 7px;
        border-radius: 999px;
        font-size: 10px;
        border: 1px solid #374151;
        color: #9ca3af;
      }
      .vsp-status-ok {
        border-color: rgba(34,197,94,0.8);
        color: #bbf7d0;
        background: rgba(22,163,74,0.12);
      }
      .vsp-status-fail {
        border-color: rgba(248,113,113,0.9);
        color: #fecaca;
        background: rgba(239,68,68,0.18);
      }
      .vsp-status-running {
        border-color: rgba(59,130,246,0.9);
        color: #bfdbfe;
        background: rgba(37,99,235,0.16);
      }
      .vsp-link {
        font-size: 11px;
        color: #93c5fd;
        text-decoration: none;
      }
      .vsp-link:hover {
        text-decoration: underline;
      }
      .vsp-link.disabled {
        opacity: 0.35;
        pointer-events: none;
        text-decoration: none;
        cursor: default;
      }
      .vsp-detail-grid {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 8px;
        margin-top: 4px;
      }
      .vsp-detail-kpi {
        padding: 6px 8px;
        border-radius: 8px;
        background: radial-gradient(circle at top left, rgba(59,130,246,0.18), transparent 55%),
                    #020617;
        border: 1px solid #111827;
      }
      .vsp-detail-kpi-label {
        font-size: 10px;
        color: #9ca3af;
      }
      .vsp-detail-kpi-value {
        font-size: 13px;
        color: #f9fafb;
        font-weight: 500;
      }
      .vsp-detail-grid-wide {
        grid-column: span 2 / span 2;
      }
      .vsp-detail-tools {
        display: flex;
        flex-wrap: wrap;
        gap: 4px;
        margin-top: 4px;
      }
      .vsp-tool-pill {
        font-size: 10px;
        padding: 2px 6px;
        border-radius: 999px;
        border: 1px solid #374151;
        color: #9ca3af;
      }
      .vsp-detail-exports {
        display: flex;
        flex-wrap: wrap;
        gap: 6px;
        margin-top: 6px;
      }
      .vsp-export-link {
        font-size: 11px;
        padding: 3px 8px;
        border-radius: 999px;
        border: 1px solid #4b5563;
        color: #e5e7eb;
        text-decoration: none;
      }
      .vsp-export-link:hover {
        border-color: #6b7280;
        background: #020617;
      }
      .vsp-export-link.disabled {
        opacity: 0.35;
        pointer-events: none;
      }
      .vsp-empty {
        font-size: 12px;
        color: #6b7280;
        padding: 10px 4px;
      }
      .vsp-error {
        font-size: 12px;
        color: #fca5a5;
        padding: 10px 4px;
      }
    `;
    const style = document.createElement('style');
    style.id = 'vsp-runs-style';
    style.textContent = css;
    document.head.appendChild(style);
  }

  function escapeHtml(str) {
    if (str == null) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function fmtTs(ts) {
    if (!ts) return '-';
    try {
      const d = new Date(ts);
      if (Number.isNaN(d.getTime())) return ts;
      return d.toLocaleString();
    } catch (e) {
      return ts;
    }
  }

  function getStatusPill(statusRaw) {
    const s = (statusRaw || '').toString().toUpperCase();
    let cls = 'vsp-status-pill';
    if (s === 'COMPLETED' || s === 'OK' || s === 'SUCCESS') cls += ' vsp-status-ok';
    else if (s === 'FAILED' || s === 'ERROR') cls += ' vsp-status-fail';
    else if (s === 'RUNNING' || s === 'IN_PROGRESS') cls += ' vsp-status-running';
    return `<span class="${cls}">${escapeHtml(s || '-')}</span>`;
  }

  function mkExportLink(url, label) {
    if (!url) {
      return `<span class="vsp-export-link disabled">${escapeHtml(label)}</span>`;
    }
    return `<a class="vsp-export-link" href="${escapeHtml(url)}" target="_blank" rel="noopener noreferrer">${escapeHtml(label)}</a>`;
  }

  function applyFilters() {
    let rows = STATE.runs.slice();

    if (STATE.filters.profile && STATE.filters.profile !== 'ALL') {
      const p = STATE.filters.profile.toLowerCase();
      rows = rows.filter(r => {
        const rp = (r.profile || r.run_profile || '').toString().toLowerCase();
        return rp.includes(p);
      });
    }

    if (STATE.filters.text) {
      const t = STATE.filters.text.toLowerCase();
      rows = rows.filter(r => {
        const rid = (r.run_id || '').toLowerCase();
        const src = (r.source || r.src || '').toLowerCase();
        return rid.includes(t) || src.includes(t);
      });
    }

    rows.sort((a, b) => {
      const ta = new Date(a.ts || a.timestamp || 0).getTime();
      const tb = new Date(b.ts || b.timestamp || 0).getTime();
      if (!Number.isNaN(ta) && !Number.isNaN(tb) && ta !== tb) {
        return tb - ta;
      }
      const ra = (a.run_id || '').toString();
      const rb = (b.run_id || '').toString();
      return rb.localeCompare(ra);
    });

    STATE.filtered = rows;

    if (!STATE.selectedRunId && rows.length > 0) {
      STATE.selectedRunId = rows[0].run_id;
    }

    renderTable();
    renderDetail();
  }

  function renderTable() {
    const tbody = document.getElementById('vsp-runs-table-body');
    const infoSpan = document.getElementById('vsp-runs-table-info');
    if (!tbody) return;

    if (!STATE.filtered.length) {
      tbody.innerHTML = '';
      if (infoSpan) infoSpan.textContent = 'Không có run nào khớp filter.';
      return;
    }

    if (infoSpan) {
      infoSpan.textContent = `Tổng ${STATE.filtered.length} run.`;
    }

    let html = '';
    STATE.filtered.forEach(run => {
      const rid = run.run_id || '-';
      const tsStr = fmtTs(run.ts || run.timestamp);
      const profile = run.profile || run.run_profile || '-';

      const sev = run.severity || run.summary?.severity || run.summary?.by_severity || {};
      const c = Number(sev.CRITICAL || 0);
      const h = Number(sev.HIGH || 0);
      const m = Number(sev.MEDIUM || 0);
      const l = Number(sev.LOW || 0);
      const info = Number(sev.INFO || 0);
      const tr = Number(sev.TRACE || 0);
      const total = Number(run.total_findings || run.total || (c+h+m+l+info+tr));

      const score = run.security_score != null
        ? Number(run.security_score).toFixed(1)
        : (run.score != null ? Number(run.score).toFixed(1) : '-');

      let tools = run.tools;
      if (!tools && run.summary && run.summary.by_tool) {
        tools = Object.keys(run.summary.by_tool).join(', ');
      }
      const toolsStr = tools || '-';

      const statusRaw = run.status || run.state || 'COMPLETED';
      const statusHtml = getStatusPill(statusRaw);

      const htmlReport = run.report_html || run.html_report || null;
      const bundleUrl = run.run_id ? ("/api/vsp/run_bundle/" + encodeURIComponent(run.run_id)) : (run.bundle_zip || run.report_zip || run.report_root || null);

      const viewLink = htmlReport
        ? `<a class="vsp-link" href="${escapeHtml(htmlReport)}" target="_blank" rel="noopener noreferrer">View</a>`
        : `<span class="vsp-link disabled">View</span>`;

      const exportLink = bundleUrl
        ? `<a class="vsp-link" href="${escapeHtml(bundleUrl)}" target="_blank" rel="noopener noreferrer">Bundle (ZIP)</a>`
        : `<span class="vsp-link disabled">Export</span>`;

      const selectedCls = (STATE.selectedRunId === rid) ? 'vsp-row-selected' : '';

      html += `
        <tr class="${selectedCls}" data-run-id="${escapeHtml(rid)}">
          <td class="vsp-mono">${escapeHtml(rid)}</td>
          <td>${escapeHtml(tsStr)}</td>
          <td>${escapeHtml(profile)}</td>
          <td style="text-align:right">${total}</td>
          <td style="text-align:right">${c}</td>
          <td style="text-align:right">${h}</td>
          <td style="text-align:right">${m}</td>
          <td style="text-align:right">${l}</td>
          <td style="text-align:right">${info}</td>
          <td style="text-align:right">${tr}</td>
          <td style="text-align:right">${escapeHtml(score)}</td>
          <td>${statusHtml}</td>
          <td>${viewLink} &nbsp; ${exportLink}</td>
          <td>${escapeHtml(toolsStr)}</td>
        </tr>
      `;
    });

    tbody.innerHTML = html;
  }

  function renderDetail() {
    const box = document.getElementById('vsp-runs-detail-box');
    if (!box) return;

    const run = STATE.filtered.find(r => r.run_id === STATE.selectedRunId);
    if (!run) {
      box.innerHTML = `<div class="vsp-empty">Chọn 1 run ở bảng bên trái để xem chi tiết.</div>`;
      return;
    }

    const rid = run.run_id || '-';
    const tsStr = fmtTs(run.ts || run.timestamp);
    const profile = run.profile || run.run_profile || '-';
    const source = run.source || run.src || '-';

    const sev = run.severity || run.summary?.severity || run.summary?.by_severity || {};
    const c = Number(sev.CRITICAL || 0);
    const h = Number(sev.HIGH || 0);
    const m = Number(sev.MEDIUM || 0);
    const l = Number(sev.LOW || 0);
    const info = Number(sev.INFO || 0);
    const tr = Number(sev.TRACE || 0);
    const total = Number(run.total_findings || run.total || (c+h+m+l+info+tr));

    const score = run.security_score != null
      ? Number(run.security_score).toFixed(1)
      : (run.score != null ? Number(run.score).toFixed(1) : '-');

    let toolsArr = [];
    if (Array.isArray(run.tools)) {
      toolsArr = run.tools;
    } else if (typeof run.tools === 'string') {
      toolsArr = run.tools.split(',').map(s => s.trim()).filter(Boolean);
    } else if (run.summary && run.summary.by_tool) {
      toolsArr = Object.keys(run.summary.by_tool);
    }

    const htmlTools = toolsArr.length
      ? toolsArr.map(t => `<span class="vsp-tool-pill">${escapeHtml(t)}</span>`).join('')
      : '<span class="vsp-empty">Không rõ tools (by_tool không có trong payload).</span>';

    const statusRaw = run.status || run.state || 'COMPLETED';
    const statusHtml = getStatusPill(statusRaw);

    const htmlReport = run.report_html || run.html_report || null;
    const jsonReport = run.report_json || run.json_report || null;
    const bundleUrl = run.run_id ? ("/api/vsp/run_bundle/" + encodeURIComponent(run.run_id)) : (run.bundle_zip || run.report_zip || run.report_root || null);

    box.innerHTML = `
      <div class="vsp-runs-header" style="margin-bottom:8px;">
        <div>
          <div class="vsp-runs-title-main" style="font-size:15px;">Run Detail</div>
          <div class="vsp-runs-title-sub">Thông tin chi tiết run đang chọn.</div>
        </div>
      </div>
      <div class="vsp-detail-grid">
        <div class="vsp-detail-kpi vsp-detail-grid-wide">
          <div class="vsp-detail-kpi-label">Run ID</div>
          <div class="vsp-detail-kpi-value vsp-mono">${escapeHtml(rid)}</div>
        </div>
        <div class="vsp-detail-kpi">
          <div class="vsp-detail-kpi-label">Thời gian</div>
          <div class="vsp-detail-kpi-value">${escapeHtml(tsStr)}</div>
        </div>
        <div class="vsp-detail-kpi">
          <div class="vsp-detail-kpi-label">Profile</div>
          <div class="vsp-detail-kpi-value">${escapeHtml(profile)}</div>
        </div>
        <div class="vsp-detail-kpi">
          <div class="vsp-detail-kpi-label">Total findings</div>
          <div class="vsp-detail-kpi-value">${total}</div>
        </div>
        <div class="vsp-detail-kpi">
          <div class="vsp-detail-kpi-label">Security Score</div>
          <div class="vsp-detail-kpi-value">${escapeHtml(score)}</div>
        </div>
        <div class="vsp-detail-kpi vsp-detail-grid-wide">
          <div class="vsp-detail-kpi-label">Source / Report Root</div>
          <div class="vsp-detail-kpi-value vsp-mono">${escapeHtml(source || bundleUrl || '-')}</div>
        </div>
        <div class="vsp-detail-kpi vsp-detail-grid-wide">
          <div class="vsp-detail-kpi-label">Status</div>
          <div class="vsp-detail-kpi-value">${statusHtml}</div>
        </div>
      </div>
      <div style="margin-top:10px;">
        <div class="vsp-detail-kpi-label">Tools</div>
        <div class="vsp-detail-tools">
          ${htmlTools}
        </div>
      </div>
      <div style="margin-top:10px;">
        <div class="vsp-detail-kpi-label">Exports</div>
        <div class="vsp-detail-exports">
          ${mkExportLink(htmlReport, 'HTML Report')}
          ${mkExportLink(jsonReport, 'JSON Summary')}
          ${mkExportLink(bundleUrl, 'Bundle / Folder')}
        </div>
      </div>
    `;
  }

  function bindEvents() {
    const profileSel = document.getElementById('vsp-runs-filter-profile');
    const textInput = document.getElementById('vsp-runs-filter-text');
    const refreshBtn = document.getElementById('vsp-runs-refresh');
    const tbody = document.getElementById('vsp-runs-table-body');

    if (profileSel) {
      profileSel.addEventListener('change', function () {
        STATE.filters.profile = this.value || 'ALL';
        applyFilters();
      });
    }
    if (textInput) {
      textInput.addEventListener('input', function () {
        STATE.filters.text = this.value || '';
        applyFilters();
      });
    }
    if (refreshBtn) {
      refreshBtn.addEventListener('click', function () {
        fetchRuns(true);
      });
    }
    if (tbody) {
      tbody.addEventListener('click', function (e) {
        const tr = e.target.closest('tr[data-run-id]');
        if (!tr) return;
        const rid = tr.getAttribute('data-run-id');
        STATE.selectedRunId = rid;
        renderTable();
        renderDetail();
      });
    }
  }

  function buildLayout() {
    const tab = document.getElementById('tab-runs');
    if (!tab) return;
    injectRunsStyles();

    tab.innerHTML = `
      <div class="vsp-runs-root">
        <div class="vsp-runs-header">
          <div>
            <div class="vsp-runs-title-main">Runs & Reports</div>
            <div class="vsp-runs-title-sub">
              Lịch sử các lần chạy VSP FULL / EXT+, phục vụ PM / QA theo dõi tiến độ và report.
            </div>
          </div>
          <div class="vsp-runs-actions">
            <button id="vsp-runs-refresh" class="vsp-btn">
              <span>⟳</span><span>Refresh</span>
            </button>
          </div>
        </div>

        <div class="vsp-runs-filters">
          <div class="vsp-runs-filter-item">
            <label for="vsp-runs-filter-profile">Profile</label>
            <select id="vsp-runs-filter-profile">
              <option value="ALL">Tất cả</option>
              <option value="FAST">FAST</option>
              <option value="EXT">EXT</option>
              <option value="EXT+">EXT+</option>
            </select>
          </div>
          <div class="vsp-runs-filter-item">
            <label for="vsp-runs-filter-text">Search</label>
            <input id="vsp-runs-filter-text" type="text" placeholder="Run ID / source...">
          </div>
          <div class="vsp-runs-filter-item">
            <label>&nbsp;</label>
            <span id="vsp-runs-table-info" style="font-size:11px;color:#6b7280;"></span>
          </div>
        </div>

        <div class="vsp-runs-main">
          <div class="vsp-card">
            <div class="vsp-card-header">
              <div>
                <div class="vsp-card-title">Run History</div>
                <div class="vsp-card-sub">Danh sách run mới nhất (sort theo thời gian).</div>
              </div>
              <div class="vsp-tag">
                <span class="vsp-tag-dot"></span>
                <span>Source: /api/vsp/runs_v2</span>
              </div>
            </div>
            <div class="vsp-table-wrap">
              <table class="vsp-table">
                <thead>
                  <tr>
                    <th>Run ID</th>
                    <th>Time</th>
                    <th>Profile</th>
                    <th style="text-align:right;">Total</th>
                    <th style="text-align:right;">CRIT</th>
                    <th style="text-align:right;">HIGH</th>
                    <th style="text-align:right;">MED</th>
                    <th style="text-align:right;">LOW</th>
                    <th style="text-align:right;">INFO</th>
                    <th style="text-align:right;">TRACE</th>
                    <th style="text-align:right;">Score</th>
                    <th>Status</th>
                    <th>Actions</th>
                    <th>Tools</th>
                  </tr>
                </thead>
                <tbody id="vsp-runs-table-body">
                  <tr><td colspan="14" class="vsp-empty">Đang tải dữ liệu run...</td></tr>
                </tbody>
              </table>
            </div>
          </div>

          <div class="vsp-card">
            <div id="vsp-runs-detail-box" style="margin-top:4px;min-height:180px;">
              <div class="vsp-empty">Chọn 1 run ở bảng bên trái để xem chi tiết.</div>
            </div>
          </div>
        </div>
      </div>
    `;

    bindEvents();
  }

  function fetchRuns(force) {
    const tbody = document.getElementById('vsp-runs-table-body');
    const infoSpan = document.getElementById('vsp-runs-table-info');
    if (tbody && force) {
      tbody.innerHTML = `<tr><td colspan="14" class="vsp-empty">Đang reload dữ liệu từ /api/vsp/runs_v2...</td></tr>`;
    }
    if (infoSpan && force) {
      infoSpan.textContent = 'Đang tải lại...';
    }

    fetch('/api/vsp/runs_v2')
      .then(res => res.json())
      .then(data => {
        const runs = Array.isArray(data.runs) ? data.runs : [];
        STATE.runs = runs;
        STATE.selectedRunId = null;
        applyFilters();
      })
      .catch(err => {
        console.error('Lỗi gọi /api/vsp/runs_v2:', err);
        if (tbody) {
          tbody.innerHTML = `<tr><td colspan="14" class="vsp-error">Lỗi khi tải /api/vsp/runs_v2 – kiểm tra backend.</td></tr>`;
        }
        if (infoSpan) {
          infoSpan.textContent = 'Lỗi tải dữ liệu.';
        }
      });
  }

  function init() {
    const tab = document.getElementById('tab-runs');
    if (!tab) return;
    injectRunsStyles();
    buildLayout();
    fetchRuns(false);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  window.VSP.initRunsTab = init;
})();
