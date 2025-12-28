// static/js/vsp_datasource_tab_v2.js
// V2 – Data Source tab, bảng unified findings + filter severity + search

(function () {
  'use strict';

  if (window.VSP_DATASOURCE_TAB_V2) return;
  window.VSP_DATASOURCE_TAB_V2 = true;

  var LOG_PREFIX = '[VSP_DS]';
  var loaded = false;
  var allItems = [];
  var currentSeverity = '';
  var currentSearch = '';

  function $(sel) { return document.querySelector(sel); }

  async function fetchDatasource() {
    try {
      var res = await fetch('/api/vsp/datasource_v2?limit=300', { cache: 'no-store' });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      return await res.json();
    } catch (e) {
      console.error(LOG_PREFIX, 'fetch error:', e);
      return null;
    }
  }

  function normalizeSeverity(s) {
    if (!s) return '';
    return String(s).toUpperCase();
  }

  function escapeHtml(str) {
    if (str === null || str === undefined) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  function itemMatchesFilters(item) {
    var sev = normalizeSeverity(item.severity || item.level || item.priority);

    if (currentSeverity && sev !== currentSeverity) return false;

    if (currentSearch) {
      var q = currentSearch.toLowerCase();
      var fields = [
        item.tool,
        item.rule_id,
        item.rule,
        item.check_id,
        item.file,
        item.file_path,
        item.target,
        item.message,
        item.summary
      ];
      for (var i = 0; i < fields.length; i++) {
        if (!fields[i]) continue;
        if (String(fields[i]).toLowerCase().indexOf(q) !== -1) return true;
      }
      return false;
    }

    return true;
  }

  function buildRows(items) {
    if (!items || !items.length) {
      return '<tr><td colspan="7" class="col-empty">Không có bản ghi nào.</td></tr>';
    }

    return items.map(function (f, idx) {
      var sev = normalizeSeverity(f.severity || f.level || f.priority);
      var tool = f.tool || f.scanner || '—';
      var rule = f.rule_id || f.rule || f.check_id || '—';
      var file = f.file || f.file_path || f.target || '—';
      var line = f.line || f.start_line || (f.location && f.location.line) || '—';
      var msg = f.message || f.summary || '';

      return [
        '<tr>',
        '  <td class="col-idx">' + (idx + 1) + '</td>',
        '  <td class="col-sev"><span class="vsp-badge vsp-badge-' + sev.toLowerCase() + '">' + (sev || '—') + '</span></td>',
        '  <td class="col-tool">' + escapeHtml(tool) + '</td>',
        '  <td class="col-rule"><code>' + escapeHtml(rule) + '</code></td>',
        '  <td class="col-file">' + escapeHtml(file) + '</td>',
        '  <td class="col-line">' + escapeHtml(line) + '</td>',
        '  <td class="col-msg">' + escapeHtml(msg) + '</td>',
        '</tr>'
      ].join('');
    }).join('\n');
  }

  function renderTable() {
    var pane = document.getElementById('vsp-datasource-main') ||
               document.getElementById('vsp-tab-datasource');
    if (!pane) {
      console.warn(LOG_PREFIX, 'Không tìm thấy pane #vsp-datasource-main hoặc #vsp-tab-datasource');
      return;
    }

    var filtered = allItems.filter(itemMatchesFilters);
    var tbody = pane.querySelector('tbody.vsp-ds-body');
    if (!tbody) return;
    tbody.innerHTML = buildRows(filtered);

    var countEl = pane.querySelector('#vsp-ds-count');
    if (countEl) {
      countEl.textContent = filtered.length + ' / ' + allItems.length;
    }
  }

  function renderPane(data) {
    var pane = document.getElementById('vsp-datasource-main') ||
               document.getElementById('vsp-tab-datasource');
    if (!pane) {
      console.warn(LOG_PREFIX, 'Không tìm thấy pane datasource.');
      return;
    }

    pane.innerHTML = '';

    if (!data) {
      pane.innerHTML = '<div class="vsp-error">Không tải được /api/vsp/datasource_v2.</div>';
      return;
    }
    if (data.ok === false && data.error) {
      pane.innerHTML = '<div class="vsp-error">' + data.error + '</div>';
      return;
    }

    allItems = data.items || data.findings || [];

    var html = [
      '<div class="vsp-card vsp-ds-card">',
      '  <div class="vsp-card-header">',
      '    <h2 class="vsp-card-title">Data Source</h2>',
      '    <p class="vsp-card-subtitle">Danh sách unified findings từ tất cả các tool.</p>',
      '  </div>',
      '  <div class="vsp-ds-filters">',
      '    <div class="vsp-ds-sev-filters">',
      '      <button type="button" class="vsp-ds-sev-btn" data-sev="">All</button>',
      '      <button type="button" class="vsp-ds-sev-btn" data-sev="CRITICAL">CRITICAL</button>',
      '      <button type="button" class="vsp-ds-sev-btn" data-sev="HIGH">HIGH</button>',
      '      <button type="button" class="vsp-ds-sev-btn" data-sev="MEDIUM">MEDIUM</button>',
      '      <button type="button" class="vsp-ds-sev-btn" data-sev="LOW">LOW</button>',
      '      <button type="button" class="vsp-ds-sev-btn" data-sev="INFO">INFO</button>',
      '      <button type="button" class="vsp-ds-sev-btn" data-sev="TRACE">TRACE</button>',
      '    </div>',
      '    <div class="vsp-ds-search">',
      '      <input type="search" id="vsp-ds-search-input" placeholder="Tìm theo rule / file / message..." />',
      '      <span class="vsp-ds-count" id="vsp-ds-count"></span>',
      '    </div>',
      '  </div>',
      '  <div class="vsp-table-wrapper vsp-ds-table-wrapper">',
      '    <table class="vsp-table vsp-table-datasource">',
      '      <thead>',
      '        <tr>',
      '          <th>#</th>',
      '          <th>Severity</th>',
      '          <th>Tool</th>',
      '          <th>Rule</th>',
      '          <th>File</th>',
      '          <th>Line</th>',
      '          <th>Message</th>',
      '        </tr>',
      '      </thead>',
      '      <tbody class="vsp-ds-body">',
      '      </tbody>',
      '    </table>',
      '  </div>',
      '</div>'
    ].join('\n');

    pane.innerHTML = html;

    // Gắn event filter
    var buttons = pane.querySelectorAll('.vsp-ds-sev-btn');
    buttons.forEach(function (btn) {
      btn.addEventListener('click', function () {
        buttons.forEach(function (b) { b.classList.remove('active'); });
        btn.classList.add('active');
        currentSeverity = btn.getAttribute('data-sev') || '';
        renderTable();
      });
    });

    var searchInput = pane.querySelector('#vsp-ds-search-input');
    if (searchInput) {
      searchInput.addEventListener('input', function () {
        currentSearch = searchInput.value.trim();
        renderTable();
      });
    }

    // Init state
    currentSeverity = '';
    currentSearch = '';
    if (buttons[0]) buttons[0].classList.add('active');
    renderTable();
  }

  async function hydrateDatasource() {
    if (loaded) return;
    var pane = document.getElementById('vsp-datasource-main') ||
               document.getElementById('vsp-tab-datasource');
    if (!pane) {
      console.warn(LOG_PREFIX, 'Pane datasource chưa sẵn sàng, bỏ qua.');
      return;
    }

    console.log(LOG_PREFIX, 'Hydrating datasource tab...');
    pane.innerHTML = '<div class="vsp-loading">Đang tải unified findings...</div>';

    var data = await fetchDatasource();
    renderPane(data);

    loaded = true;
    console.log(LOG_PREFIX, 'Datasource tab hydrated.');
  }

  function shouldHydrateNow() {
    return (window.location.hash === '#datasource');
  }

  function onReady() {
    console.log(LOG_PREFIX, 'vsp_datasource_tab_v2.js loaded');
    if (shouldHydrateNow()) {
      hydrateDatasource();
    }
  }

  function onHashChange() {
    if (shouldHydrateNow()) {
      hydrateDatasource();
    }
  }

  window.addEventListener('DOMContentLoaded', onReady);
  window.addEventListener('hashchange', onHashChange);
})();
