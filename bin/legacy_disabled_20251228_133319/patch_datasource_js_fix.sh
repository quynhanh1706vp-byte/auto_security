#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

JS="static/datasource_sample_table.js"

cat > "$JS" <<'JS'
(function () {
  const host = window.location.origin;

  function guessRunIdFromSummary(summary) {
    return summary.run_id || summary.RUN || summary.run || summary.last_run || null;
  }

  function buildFindingPaths(runId) {
    // Thử lần lượt: findings_unified.json → findings.json
    return [
      `/out/${runId}/report/findings_unified.json`,
      `/out/${runId}/report/findings.json`
    ];
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

  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  function renderTable(container, rows, runId) {
    if (!rows || !rows.length) {
      container.innerHTML =
        '<span style="font-size:12px;opacity:.7">Không tìm thấy record nào trong findings JSON của ' +
        (runId || 'RUN mới nhất') + '.</span>';
      return;
    }

    const maxRows = 40;
    const slice = rows.slice(0, maxRows);

    let html = '<table>';
    html += '<thead><tr>' +
            '<th>Tool</th><th>Severity</th><th>Rule</th><th>Location</th><th>Message</th>' +
            '</tr></thead><tbody>';

    for (const rec of slice) {
      const tool     = rec.tool || rec.Tool || rec.TOOL || '';
      const rule     = rec.rule || rec.rule_id || rec.Rule || '';
      const location = rec.location || rec.path || rec.file || '';
      const message  = rec.message || rec.msg || rec.description || '';

      const sevRaw = rec.severity || rec.Severity || rec.SEV || '';
      const sev    = normalizeSeverity(sevRaw);

      html += '<tr>';
      html += `<td>${escapeHtml(tool)}</td>`;
      html += `<td class="${sev.cls}">${escapeHtml(sev.text)}</td>`;
      html += `<td>${escapeHtml(rule)}</td>`;
      html += `<td>${escapeHtml(location)}</td>`;
      html += `<td>${escapeHtml(message)}</td>`;
      html += '</tr>';
    }

    html += '</tbody></table>';

    if (rows.length > maxRows) {
      html += `<div style="margin-top:6px;font-size:11px;opacity:.7">Hiển thị ${maxRows}/${rows.length} bản ghi đầu tiên.</div>`;
    }

    container.innerHTML = html;
  }

  async function loadFindingsForRun(runId) {
    const paths = buildFindingPaths(runId);
    let lastErr = null;

    for (const p of paths) {
      try {
        const resp = await fetch(`${host}${p}`);
        if (!resp.ok) {
          lastErr = `HTTP ${resp.status} cho ${p}`;
          continue;
        }
        const data = await resp.json();
        if (!Array.isArray(data)) {
          lastErr = `${p} không phải mảng JSON`;
          continue;
        }
        return { rows: data, path: p };
      } catch (err) {
        lastErr = String(err);
      }
    }
    throw new Error(lastErr || 'Không đọc được bất kỳ file findings JSON nào');
  }

  async function loadSample() {
    const container = document.getElementById('ds-sample-table');
    if (!container) return;

    try {
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

      const { rows } = await loadFindingsForRun(runId);
      renderTable(container, rows, runId);
    } catch (err) {
      console.error('[DataSource] load sample error:', err);
      container.innerHTML =
        '<span style="font-size:12px;opacity:.7">Lỗi khi tải sample findings (xem console log).</span>';
    }
  }

  document.addEventListener('DOMContentLoaded', loadSample);
})();
JS

echo "[OK] Đã cập nhật static/datasource_sample_table.js (fallback findings.json)."
