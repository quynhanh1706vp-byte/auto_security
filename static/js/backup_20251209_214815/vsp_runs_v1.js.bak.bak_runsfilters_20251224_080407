/**
 * VSP Runs & Reports – NEW IMPLEMENTATION (mass replace)
 * Không còn loadRunsTable, không còn VSP_RUNS_UI_v1.
 */
(function () {
  'use strict';

  function $(sel) {
    return document.querySelector(sel);
  }

  function deriveRunsArray(data) {
    if (!data) return [];
    if (Array.isArray(data)) return data;
    if (Array.isArray(data.items)) return data.items;
    if (Array.isArray(data.runs)) return data.runs;
    if (Array.isArray(data.last_runs)) return data.last_runs;
    return [];
  }

  function average(list) {
    if (!list.length) return null;
    var s = 0;
    for (var i = 0; i < list.length; i++) s += list[i];
    return s / list.length;
  }

  function renderKpis(runs) {
    var totalSpan = $('#vsp-kpi-runs-total');
    var last10Span = $('#vsp-kpi-runs-last10');
    var avgFindSpan = $('#vsp-kpi-runs-avg-findings');
    var toolsPerRunSpan = $('#vsp-kpi-runs-tools-per-run');

    var totalRuns = runs.length;
    var last10 = runs.slice(0, 10);

    var findingsList = [];
    var toolsCounts = [];

    runs.forEach(function (run) {
      var f = run.total_findings;
      if (f == null) f = run.findings_total;
      if (f == null && run.summary && run.summary.total_findings != null) {
        f = run.summary.total_findings;
      }
      if (typeof f === 'number') findingsList.push(f);

      var tools = run.tools_enabled || run.tools;
      if (Array.isArray(tools)) {
        toolsCounts.push((new Set(tools)).size);
      }
    });

    if (totalSpan) totalSpan.textContent = String(totalRuns);
    if (last10Span) last10Span.textContent = String(last10.length);

    var avgFind = average(findingsList);
    if (avgFindSpan) avgFindSpan.textContent = (avgFind != null ? avgFind.toFixed(1) : '–');

    var avgTools = average(toolsCounts);
    if (toolsPerRunSpan) toolsPerRunSpan.textContent = (avgTools != null ? avgTools.toFixed(1) : '–');
  }

  function renderTable(runs) {
    var tbody = $('#vsp-runs-tbody');
    if (!tbody) {
      console.log('[VSP_RUNS_TAB] Không tìm thấy #vsp-runs-tbody – bỏ qua render bảng.');
      return;
    }

    tbody.innerHTML = '';

    if (!runs.length) {
      var trEmpty = document.createElement('tr');
      var td = document.createElement('td');
      td.colSpan = 12;
      td.textContent = 'Chưa có VSP run nào.';
      trEmpty.appendChild(td);
      tbody.appendChild(trEmpty);
      return;
    }

    runs.forEach(function (run, idx) {
      var tr = document.createElement('tr');

      function cell(text) {
        var td = document.createElement('td');
        td.textContent = text;
        return td;
      }

      var id = run.run_id || run.id || run.name || '–';
      var created = run.created_at || run.started_at || run.time || run.started || '';
      var profile = run.profile || run.scan_profile || '–';

      var f = run.total_findings;
      if (f == null) f = run.findings_total;
      if (f == null && run.summary && run.summary.total_findings != null) {
        f = run.summary.total_findings;
      }

      var tools = run.tools_enabled || run.tools;
      var toolsText = Array.isArray(tools) ? tools.join(', ') : (tools || '');

      tr.setAttribute('data-run-id', id);

      tr.appendChild(cell(String(idx + 1)));
      tr.appendChild(cell(id));
      tr.appendChild(cell(created || ''));
      tr.appendChild(cell(profile));
      tr.appendChild(cell(f != null ? String(f) : ''));
      tr.appendChild(cell(toolsText));

      tbody.appendChild(tr);
    });
  }

  async function loadRuns() {
    var placeholder = $('#vsp-runs-loading');
    if (placeholder) placeholder.textContent = 'Đang load danh sách runs...';

    try {
      var res = await fetch('/api/vsp/runs_index_v3');
      if (!res.ok) {
        console.error('[VSP_RUNS_TAB] HTTP', res.status, 'khi gọi runs_index_v3');
        if (placeholder) {
          placeholder.textContent = 'Lỗi HTTP ' + res.status + ' khi load runs_index_v3.';
        }
        return;
      }

      var data = await res.json();
      var runs = deriveRunsArray(data);
      if (placeholder) placeholder.textContent = '';

      console.log('[VSP_RUNS_TAB] Loaded ' + runs.length + ' runs từ runs_index_v3');
      renderKpis(runs);
      renderTable(runs);
    } catch (err) {
      console.error('[VSP_RUNS_TAB] Lỗi fetch runs_index_v3', err);
      if (placeholder) placeholder.textContent = 'Lỗi khi load runs: ' + err;
    }
  }

  document.addEventListener('DOMContentLoaded', function () {
    console.log('[VSP_RUNS_TAB] vsp_runs_v1.js (mass replace) loaded – auto load runs.');
    loadRuns();
    window.vspReloadRuns = loadRuns;
  });
})();
