#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
JS="$ROOT/static/js/vsp_datasource_filters_v2.js"

echo "[PATCH] Ghi đè $JS để TAB Data Source dùng data thật từ datasource_v2"

cat > "$JS" << 'JS'
// VSP_DATASOURCE_REAL_V3 – bind Data Source tab với /api/vsp/dashboard_v3 + /api/vsp/datasource_v2
(function() {
  const LOG_PREFIX = "[VSP_DATA_TAB]";

  function log() {
    if (window.console && console.log) {
      console.log.apply(console, [LOG_PREFIX].concat(Array.from(arguments)));
    }
  }

  async function getLatestRunId() {
    try {
      const resp = await fetch('/api/vsp/dashboard_v3');
      if (!resp.ok) {
        log('dashboard_v3 HTTP error', resp.status);
        return null;
      }
      const data = await resp.json();
      log('/api/vsp/dashboard_v3 =>', data);
      return data.run_id || null;
    } catch (e) {
      log('getLatestRunId error', e);
      return null;
    }
  }

  async function fetchDatasourceItems(runId, limit) {
    const runDir = '/home/test/Data/SECURITY_BUNDLE/out/' + runId;
    const qs = new URLSearchParams({
      run_dir: runDir,
      limit: String(limit || 500)
    });

    const url = '/api/vsp/datasource_v2?' + qs.toString();
    log('Fetch datasource_v2 với', url);

    const resp = await fetch(url);
    if (!resp.ok) {
      log('datasource_v2 HTTP error', resp.status);
      throw new Error('HTTP ' + resp.status);
    }
    const data = await resp.json();
    log('datasource_v2 payload', data);

    if (Array.isArray(data.items)) {
      return data.items;
    }
    if (Array.isArray(data.data)) {
      return data.data;
    }
    return [];
  }

  function getDatasourceTbody() {
    const tab = document.getElementById('tab-data');
    if (!tab) return null;
    const table = tab.querySelector('table.vsp-table');
    if (!table) return null;
    return table.querySelector('tbody');
  }

  function renderDatasourceTable(items) {
    const tbody = getDatasourceTbody();
    if (!tbody) {
      log('Không tìm thấy tbody trong TAB Data Source');
      return;
    }

    tbody.innerHTML = '';

    if (!items.length) {
      const tr = document.createElement('tr');
      const td = document.createElement('td');
      td.colSpan = 11;
      td.textContent = 'Không có findings cho run hiện tại.';
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }

    items.forEach(function(it) {
      const tr = document.createElement('tr');

      function td(text) {
        const el = document.createElement('td');
        el.textContent = (text === null || text === undefined) ? '' : String(text);
        return el;
      }

      const sev    = it.severity_norm || it.severity || '';
      const tool   = it.tool || '';
      const file   = it.file || it.path || '';
      const line   = it.line || '';
      const rule   = it.rule_id || it.rule || '';
      const msg    = it.message || '';
      const cwe    = it.cwe || '';
      const cve    = Array.isArray(it.cves) ? it.cves.join(',') : (it.cve || '');
      const module = it.module || '';
      const fix    = it.fix || it.recommendation || '';
      const tags   = Array.isArray(it.tags) ? it.tags.join(',') : (it.tags || '');

      tr.appendChild(td(sev));
      tr.appendChild(td(tool));
      tr.appendChild(td(file));
      tr.appendChild(td(line));
      tr.appendChild(td(rule));
      tr.appendChild(td(msg));
      tr.appendChild(td(cwe));
      tr.appendChild(td(cve));
      tr.appendChild(td(module));
      tr.appendChild(td(fix));
      tr.appendChild(td(tags));

      tbody.appendChild(tr);
    });
  }

  async function loadDataTabOnce() {
    try {
      log('Bắt đầu load Data Source tab...');
      const runId = await getLatestRunId();
      if (!runId) {
        log('Không lấy được run_id từ dashboard_v3, bỏ qua.');
        return;
      }
      log('Dùng run_id =', runId);

      const items = await fetchDatasourceItems(runId, 500);
      log('Nhận được', items.length, 'items từ datasource_v2');
      renderDatasourceTable(items);
    } catch (e) {
      log('Lỗi loadDataTabOnce', e);
    }
  }

  function bindTabHook() {
    const btn = document.querySelector('.vsp-tab-btn[data-tab="tab-data"]');
    if (!btn) {
      log('Không tìm thấy tab button cho TAB Data Source');
      return;
    }

    let loaded = false;
    btn.addEventListener('click', function() {
      if (loaded) return;
      loaded = true;
      log('switch to tab-data → trigger loadDataTabOnce');
      loadDataTabOnce();
    });
  }

  document.addEventListener('DOMContentLoaded', bindTabHook);
})();
JS

echo "[PATCH] Đã ghi $JS"
