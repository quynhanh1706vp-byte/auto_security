#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

echo "[i] ROOT = $ROOT"

TPL="templates/datasource.html"
JS="static/datasource_sample_table.js"

#############################################
# 1) Ghi lại template datasource.html
#    - Sidebar 4 tab
#    - Card phẳng
#    - Có placeholder #ds-sample-table để JS đổ bảng thật
#############################################
cat > "$TPL" <<'HTML'
<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="utf-8">
  <title>SECURITY BUNDLE – Data Source</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="/static/css/security_resilient.css">
  <style>
    :root {
      --sb-bg: #02050a;
      --sb-border-subtle: rgba(0, 255, 180, 0.16);
      --sb-text-main: #f5fff9;
      --sb-text-soft: #7da4a0;
      --sb-shadow-soft: 0 14px 32px rgba(0, 0, 0, 0.8);
    }
    * { box-sizing: border-box; }
    html, body { margin:0; padding:0; width:100%; height:100%; }
    body {
      font-family: system-ui,-apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",sans-serif;
      color: var(--sb-text-main);
      background:
        radial-gradient(circle at top left, rgba(25,189,148,0.32) 0, transparent 45%),
        radial-gradient(circle at bottom right, rgba(0,102,204,0.42) 0, #02050a 60%);
      min-height: 100vh;
      overflow-x: hidden;
    }

    .sb-page   { width:100vw; max-width:100vw; padding:12px 18px 20px; }
    .sb-layout { display:flex; align-items:flex-start; gap:16px; width:100%; }

    /* SIDEBAR */
    .sb-sidebar {
      width:190px;
      min-height:520px;
      background:linear-gradient(180deg,rgba(7,40,34,0.95),rgba(3,15,15,0.98));
      border-radius:0;
      border:1px solid rgba(54,211,168,0.45);
      box-shadow:var(--sb-shadow-soft);
      padding:10px 10px 12px;
    }
    .sb-sidebar-logo {
      font-size:12px;
      letter-spacing:.14em;
      text-transform:uppercase;
      color:var(--sb-text-soft);
      border-bottom:1px solid rgba(54,211,168,0.4);
      padding-bottom:8px;
      margin-bottom:8px;
    }
    .sb-sidebar-logo span {
      display:block;
      font-size:11px;
      opacity:.75;
      margin-top:2px;
    }
    .sb-sidebar-nav {
      display:flex;
      flex-direction:column;
      gap:6px;
    }
    .sb-nav-link {
      display:block;
      padding:6px 8px;
      font-size:12px;
      text-decoration:none;
      color:var(--sb-text-soft);
      text-transform:uppercase;
      letter-spacing:.12em;
      border-radius:0;
      border:1px solid transparent;
    }
    .sb-nav-link:hover {
      border-color:rgba(54,211,168,0.4);
      color:#f6fff9;
      background:rgba(5,18,18,0.9);
    }
    .sb-nav-link-active {
      border-color:rgba(54,211,168,0.9);
      color:#eafff7;
      background:rgba(5,32,26,0.98);
    }

    /* MAIN */
    .sb-main-wrapper {
      flex:1;
      display:flex;
      flex-direction:column;
      gap:10px;
    }
    .sb-header {
      display:flex;
      justify-content:space-between;
      align-items:center;
      gap:12px;
      margin-bottom:4px;
    }
    .sb-header-title {
      padding:8px 14px;
      border-radius:0;
      background:linear-gradient(90deg,rgba(54,211,168,0.3),transparent 70%);
      border:1px solid rgba(54,211,168,0.5);
      font-size:13px;
      letter-spacing:.08em;
      text-transform:uppercase;
      color:var(--sb-text-soft);
      box-shadow:var(--sb-shadow-soft);
    }
    .sb-header-title span {
      display:block;
      font-size:11px;
      opacity:.75;
    }

    .sb-card {
      border-radius:0;
      background:linear-gradient(135deg,rgba(9,33,40,0.9),rgba(4,11,15,0.95));
      border:0;
      box-shadow:var(--sb-shadow-soft);
      padding:16px 18px 18px;
      width:100%;
      max-width:100%;
    }
    .sb-card-header {
      display:flex;
      justify-content:space-between;
      align-items:baseline;
      margin-bottom:10px;
      gap:10px;
    }
    .sb-card-header h1 {
      font-size:13px;
      letter-spacing:.16em;
      text-transform:uppercase;
      margin:0;
      color:#e9fff7;
    }
    .sb-pill {
      font-size:11px;
      padding:3px 7px;
      border-radius:0;
      background:rgba(7,43,34,0.9);
      border:1px solid rgba(54,211,168,0.3);
      color:var(--sb-text-soft);
      text-transform:uppercase;
      letter-spacing:.12em;
    }
    .sb-card-body { font-size:13px; color:var(--sb-text-soft); }

    .ds-table {
      width:100%;
      border-collapse:collapse;
      margin-bottom:12px;
      font-size:13px;
    }
    .ds-table td {
      padding:4px 8px;
      vertical-align:top;
    }
    .ds-table td:first-child {
      width:140px;
      text-transform:uppercase;
      letter-spacing:.08em;
      font-size:11px;
      color:#e9fff7;
    }
    .ds-table tr:nth-child(odd) td {
      background:rgba(0,25,15,0.8);
    }
    .ds-table tr:nth-child(even) td {
      background:rgba(0,22,16,0.9);
    }
    .ds-table td:nth-child(2) {
      color:#f5fff9;
      white-space:nowrap;
    }
    .ds-table td:nth-child(3) {
      color:var(--sb-text-soft);
      font-size:12px;
    }

    .ds-section-title {
      margin-top:10px;
      margin-bottom:4px;
      font-size:12px;
      letter-spacing:.14em;
      text-transform:uppercase;
      color:#e9fff7;
    }
    .ds-text {
      font-size:12px;
      color:var(--sb-text-soft);
      margin-bottom:6px;
    }

    /* Sample table từ JSON thật */
    #ds-sample-table {
      margin-top:8px;
      font-size:12px;
    }
    #ds-sample-table table {
      width:100%;
      border-collapse:collapse;
    }
    #ds-sample-table th,
    #ds-sample-table td {
      padding:4px 6px;
      text-align:left;
      vertical-align:top;
    }
    #ds-sample-table thead tr {
      border-bottom:1px solid rgba(54,211,168,0.35);
    }
    #ds-sample-table th {
      font-size:11px;
      text-transform:uppercase;
      letter-spacing:.10em;
      color:rgba(207,255,237,0.9);
    }
    #ds-sample-table tbody tr:nth-child(odd) {
      background:rgba(1,25,18,0.9);
    }
    #ds-sample-table tbody tr:nth-child(even) {
      background:rgba(0,18,14,0.95);
    }
    #ds-sample-table .sev-critical { color:#ff6b81; }
    #ds-sample-table .sev-high     { color:#ffb347; }
    #ds-sample-table .sev-medium   { color:#ffd76b; }
    #ds-sample-table .sev-low      { color:#9fe6a0; }
    #ds-sample-table .sev-info     { color:#a0c4ff; }

    @media (max-width:1100px){
      .sb-layout{flex-direction:column;}
      .sb-sidebar{
        width:100%;
        min-height:auto;
        display:flex;
        align-items:center;
      }
      .sb-sidebar-nav{
        flex-direction:row;
        margin-left:12px;
      }
    }
  </style>
</head>
<body>
  <div class="sb-page">
    <div class="sb-layout">

      <!-- SIDEBAR -->
      <aside class="sb-sidebar">
        <div class="sb-sidebar-logo">
          SECURITY BUNDLE
          <span>Dashboard &amp; reports</span>
        </div>
        <nav class="sb-sidebar-nav">
          <a href="/"           class="sb-nav-link">Dashboard</a>
          <a href="/runs"       class="sb-nav-link">Runs &amp; Reports</a>
          <a href="/settings"   class="sb-nav-link">Settings</a>
          <a href="/datasource" class="sb-nav-link sb-nav-link-active">Data Source</a>
        </nav>
      </aside>

      <!-- MAIN -->
      <div class="sb-main-wrapper">
        <header class="sb-header">
          <div class="sb-header-title">
            Data Source – UI input
            <span>Mô tả &amp; sample data từ findings_unified.json (RUN mới nhất)</span>
          </div>
        </header>

        <main>
          <section class="sb-card">
            <div class="sb-card-header">
              <h1>DATA SOURCE – UI INPUT</h1>
              <span class="sb-pill">Read only</span>
            </div>
            <div class="sb-card-body">
              <table class="ds-table">
                <tr>
                  <td>RUN ROOT</td>
                  <td>/home/test/Data/SECURITY_BUNDLE/out</td>
                  <td>Thư mục chứa các RUN_* (RUN_YYYYmmdd_HHmmSS).</td>
                </tr>
                <tr>
                  <td>UI ROOT</td>
                  <td>/home/test/Data/SECURITY_BUNDLE/ui</td>
                  <td>Nơi đặt templates/static/script UI.</td>
                </tr>
                <tr>
                  <td>JSON FINDINGS</td>
                  <td>findings_unified.json</td>
                  <td>File JSON chính, mỗi record gồm tool, severity, rule, location, message…</td>
                </tr>
                <tr>
                  <td>SUMMARY JSON</td>
                  <td>summary_unified.json</td>
                  <td>JSON tổng hợp theo RUN dùng cho Dashboard (cards, charts…).</td>
                </tr>
                <tr>
                  <td>REPORT HTML</td>
                  <td>
                    pm_style_report.html<br>
                    security_resilient.html<br>
                    simple_report.html
                  </td>
                  <td>Các template HTML dùng để generate report cho từng RUN. Tab Runs &amp; Reports sẽ link tới các file này.</td>
                </tr>
              </table>

              <div class="ds-section-title">Sample Findings – ví dụ render từ JSON thật</div>
              <div class="ds-text">
                UI sẽ lấy ~20–40 bản ghi đầu từ <code>findings_unified.json</code> của RUN mới nhất
                và hiển thị dưới dạng bảng để bạn kiểm tra nhanh cấu trúc dữ liệu.
              </div>

              <!-- Bảng sample sẽ được JS đổ vào đây -->
              <div id="ds-sample-table">
                <span style="font-size:12px;opacity:.7">Đang tải sample findings…</span>
              </div>

            </div>
          </section>
        </main>
      </div>

    </div>
  </div>

  <script src="/static/datasource_sample_table.js?v=20251125"></script>
</body>
</html>
HTML

#############################################
# 2) JS: đọc RUN mới nhất + lấy findings_unified.json thật
#############################################
cat > "$JS" <<'JS'
(function () {
  const host = window.location.origin;

  function guessRunIdFromSummary(summary) {
    // thử nhiều key khác nhau để tương thích các version
    return summary.run_id || summary.RUN || summary.run || summary.last_run || null;
  }

  function buildFindingsPath(runId) {
    // theo chuẩn out/RUN_xxx/report/findings_unified.json
    return `/out/${runId}/report/findings_unified.json`;
  }

  function normalizeSeverity(sev) {
    if (!sev) return { text: '', cls: '' };
    const s = String(sev).toLowerCase();
    if (s.startsWith('crit'))   return { text: sev, cls: 'sev-critical' };
    if (s.startsWith('high'))   return { text: sev, cls: 'sev-high' };
    if (s.startsWith('med'))    return { text: sev, cls: 'sev-medium' };
    if (s.startsWith('low'))    return { text: sev, cls: 'sev-low' };
    if (s.startsWith('info'))   return { text: sev, cls: 'sev-info' };
    return { text: sev, cls: '' };
  }

  function renderTable(container, rows, runId) {
    if (!rows || !rows.length) {
      container.innerHTML = '<span style="font-size:12px;opacity:.7">Không tìm thấy record nào trong findings_unified.json của ' +
        (runId || 'RUN mới nhất') + '.</span>';
      return;
    }

    const maxRows = 40;
    const slice = rows.slice(0, maxRows);

    let html = '';
    html += '<table>';
    html += '<thead><tr>';
    html += '<th>Tool</th><th>Severity</th><th>Rule</th><th>Location</th><th>Message</th>';
    html += '</tr></thead><tbody>';

    for (const rec of slice) {
      const tool = rec.tool || rec.Tool || rec.TOOL || '';
      const rule = rec.rule || rec.rule_id || rec.Rule || '';
      const location = rec.location || rec.path || rec.file || '';
      const message = rec.message || rec.msg || rec.description || '';

      const sevRaw = rec.severity || rec.Severity || rec.SEV || '';
      const sev = normalizeSeverity(sevRaw);

      html += '<tr>';
      html += `<td>${escapeHtml(String(tool))}</td>`;
      html += `<td class="${sev.cls}">${escapeHtml(String(sev.text))}</td>`;
      html += `<td>${escapeHtml(String(rule))}</td>`;
      html += `<td>${escapeHtml(String(location))}</td>`;
      html += `<td>${escapeHtml(String(message))}</td>`;
      html += '</tr>';
    }

    html += '</tbody></table>';

    if (rows.length > maxRows) {
      html += `<div style="margin-top:6px;font-size:11px;opacity:.7">Hiển thị ${maxRows}/${rows.length} bản ghi đầu tiên.</div>`;
    }

    container.innerHTML = html;
  }

  function escapeHtml(str) {
    return str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  async function loadSample() {
    const container = document.getElementById('ds-sample-table');
    if (!container) return;

    try {
      // 1) lấy last_summary_unified.json để biết RUN mới nhất
      const sumResp = await fetch(`${host}/static/last_summary_unified.json?ts=${Date.now()}`);
      if (!sumResp.ok) {
        container.innerHTML = '<span style="font-size:12px;opacity:.7">Không đọc được last_summary_unified.json.</span>';
        return;
      }
      const summary = await sumResp.json();
      const runId = guessRunIdFromSummary(summary) || summary.run || summary.last_run;

      if (!runId) {
        container.innerHTML = '<span style="font-size:12px;opacity:.7">Không xác định được RUN mới nhất từ last_summary_unified.json.</span>';
        return;
      }

      const findingsPath = buildFindingsPath(runId);
      const resp = await fetch(`${host}${findingsPath}`);
      if (!resp.ok) {
        container.innerHTML = '<span style="font-size:12px;opacity:.7">Không đọc được ' +
          findingsPath + ' (HTTP ' + resp.status + ').</span>';
        return;
      }

      const data = await resp.json();
      if (!Array.isArray(data)) {
        container.innerHTML = '<span style="font-size:12px;opacity:.7">findings_unified.json không phải mảng JSON, không render được.</span>';
        return;
      }

      renderTable(container, data, runId);

    } catch (err) {
      console.error('[DataSource] load sample error:', err);
      const container = document.getElementById('ds-sample-table');
      if (container) {
        container.innerHTML = '<span style="font-size:12px;opacity:.7">Lỗi khi tải sample findings (xem console log).</span>';
      }
    }
  }

  document.addEventListener('DOMContentLoaded', loadSample);
})();
JS

echo "[OK] Đã ghi $TPL và $JS (Data Source dùng data thật từ findings_unified.json)."
