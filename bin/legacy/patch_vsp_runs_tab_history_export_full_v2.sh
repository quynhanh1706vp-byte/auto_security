#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$UI_ROOT/static/js/vsp_runs_tab_v1.js"

if [[ ! -f "$TARGET" ]]; then
  echo "[ERR] Không tìm thấy $TARGET"
  exit 1
fi

BACKUP="${TARGET}.bak_history_export_v2_$(date +%Y%m%d_%H%M%S)"
cp "$TARGET" "$BACKUP"
echo "[BACKUP] $TARGET -> $BACKUP"

cat > "$TARGET" << 'JS'
// vsp_runs_tab_v1.js
// [VSP_RUNS_TAB] Commercial Runs & Reports - history + export V2 (DOM fallback)

(function () {
  'use strict';

  const LOG_PREFIX = '[VSP_RUNS_TAB]';
  const RUNS_API   = '/api/vsp/runs_index_v3';
  const EXPORT_API = '/api/vsp/run_export_v3';

  let currentRunId = null;
  let currentRunItem = null;

  function log() {
    console.log.apply(console, [LOG_PREFIX].concat(Array.from(arguments)));
  }

  function $(sel) {
    return document.querySelector(sel);
  }

  function setText(sel, val) {
    const el = $(sel);
    if (!el) return;
    el.textContent = val;
  }

  function getRunsTbody() {
    // Ưu tiên ID chuẩn
    let tbody = document.querySelector('#vsp-runs-table-body');
    if (tbody) return tbody;

    // Thử tìm tbody trong tab Runs
    const tab = document.querySelector('#vsp-tab-runs');
    if (!tab) return null;

    tbody = tab.querySelector('table tbody') || tab.querySelector('tbody');
    return tbody;
  }

  function computeKpi(items) {
    const totalRuns = items.length;

    let totalFindings = 0;
    let runsWithCriticalHigh = 0;

    items.forEach(function (item) {
      const total =
        item.total_findings ??
        item.total ??
        item.findings_total ??
        0;

      totalFindings += Number(total) || 0;

      const maxSev =
        item.severity_max ||
        item.max_severity ||
        item.max_severity_level ||
        '';

      if (typeof maxSev === 'string' &&
          (maxSev.includes('CRITICAL') || maxSev.includes('HIGH'))) {
        runsWithCriticalHigh += 1;
      }
    });

    const avgFindings = totalRuns > 0
      ? Math.round(totalFindings / totalRuns)
      : 0;

    return {
      totalRuns: totalRuns,
      totalFindings: totalFindings,
      runsWithCriticalHigh: runsWithCriticalHigh,
      avgFindings: avgFindings
    };
  }

  function selectRun(runId, item, tr) {
    currentRunId = runId;
    currentRunItem = item || null;

    document.querySelectorAll('.vsp-run-row.vsp-run-selected').forEach(function (row) {
      row.classList.remove('vsp-run-selected');
    });

    if (tr) {
      tr.classList.add('vsp-run-selected');
    }

    log('Selected run', runId);
  }

  function attachRowEvents(tr, runId, item) {
    tr.addEventListener('click', function () {
      selectRun(runId, item, tr);
    });

    tr.addEventListener('dblclick', function () {
      selectRun(runId, item, tr);
      doExport('html');
    });
  }

  function renderRunsTable(items) {
    const tbody = getRunsTbody();
    if (!tbody) {
      log('Không tìm thấy tbody Runs – skip render');
      return;
    }

    tbody.innerHTML = '';

    items.forEach(function (item, idx) {
      const tr = document.createElement('tr');
      tr.classList.add('vsp-run-row');

      if (idx === 0) {
        tr.classList.add('vsp-run-latest');
      }

      const runId =
        item.run_id ||
        item.id ||
        item.name ||
        '-';

      const profile =
        item.profile ||
        item.scan_profile ||
        item.run_profile ||
        '-';

      const posture =
        item.posture_score ??
        item.posture ??
        item.security_posture ??
        '';

      const total =
        item.total_findings ??
        item.total ??
        item.findings_total ??
        0;

      const maxSev =
        item.severity_max ||
        item.max_severity ||
        item.max_severity_level ||
        '-';

      const startedAt =
        item.started_at ||
        item.started ||
        item.created_at ||
        '';

      const cells = [
        runId,
        profile,
        posture === '' ? '-' : posture,
        total,
        maxSev,
        startedAt
      ];

      cells.forEach(function (text) {
        const td = document.createElement('td');
        td.textContent = text;
        tr.appendChild(td);
      });

      attachRowEvents(tr, runId, item);

      tbody.appendChild(tr);

      if (idx === 0) {
        selectRun(runId, item, tr);
      }
    });
  }

  function doExport(fmt) {
    if (!currentRunId) {
      alert('Hãy chọn 1 run trong bảng trước khi export.');
      return;
    }

    const url = new URL(EXPORT_API, window.location.origin);
    url.searchParams.set('run_id', currentRunId);
    url.searchParams.set('fmt', fmt);

    log('Export', fmt, 'run', currentRunId, '->', url.toString());

    if (fmt === 'html') {
      window.open(url.toString(), '_blank');
    } else {
      window.location.href = url.toString();
    }
  }

  function ensureExportToolbar() {
    const root =
      document.querySelector('#vsp-tab-runs') ||
      document.querySelector('#vsp-runs-panel') ||
      document.querySelector('#vsp-runs');

    if (!root) {
      log('Không tìm thấy container Runs tab để gắn toolbar export – skip');
      return;
    }

    if (root.querySelector('#vsp-run-export-html')) {
      return;
    }

    const toolbar = document.createElement('div');
    toolbar.className = 'vsp-runs-toolbar';

    const btnHtml = document.createElement('button');
    btnHtml.type = 'button';
    btnHtml.id = 'vsp-run-export-html';
    btnHtml.textContent = 'Export HTML';
    btnHtml.addEventListener('click', function () {
      doExport('html');
    });

    const btnZip = document.createElement('button');
    btnZip.type = 'button';
    btnZip.id = 'vsp-run-export-zip';
    btnZip.textContent = 'Export ZIP';
    btnZip.addEventListener('click', function () {
      doExport('zip');
    });

    const btnCsv = document.createElement('button');
    btnCsv.type = 'button';
    btnCsv.id = 'vsp-run-export-csv';
    btnCsv.textContent = 'Export CSV';
    btnCsv.addEventListener('click', function () {
      doExport('csv');
    });

    toolbar.appendChild(btnHtml);
    toolbar.appendChild(btnZip);
    toolbar.appendChild(btnCsv);

    root.insertBefore(toolbar, root.firstChild);

    log('Export toolbar attached vào Runs tab');
  }

  async function loadRunsHistory() {
    const tbody = getRunsTbody();
    if (!tbody) {
      log('Không có DOM Runs tbody – skip init history');
      return;
    }

    try {
      const url = new URL(RUNS_API, window.location.origin);
      url.searchParams.set('limit', '50');

      log('Fetching runs from', url.toString());

      const res = await fetch(url.toString(), {
        method: 'GET',
        headers: {
          Accept: 'application/json'
        }
      });

      if (!res.ok) {
        log('Fetch runs thất bại, status =', res.status);
        return;
      }

      const data = await res.json();
      if (!data || !Array.isArray(data.items)) {
        log('Payload không hợp lệ (không có items[])', data);
        return;
      }

      const items = data.items;
      log('Nhận được', items.length, 'runs');

      const k = computeKpi(items);
      setText('#vsp-runs-kpi-total', String(k.totalRuns));
      setText('#vsp-runs-kpi-critical-high', String(k.runsWithCriticalHigh));
      setText('#vsp-runs-kpi-avg-findings', String(k.avgFindings));

      renderRunsTable(items);
      ensureExportToolbar();
    } catch (err) {
      console.error(LOG_PREFIX, 'Lỗi loadRunsHistory:', err);
    }
  }

  function init() {
    if (window.__VSP_RUNS_TAB_HISTORY_EXPORT_INITED__) {
      return;
    }
    window.__VSP_RUNS_TAB_HISTORY_EXPORT_INITED__ = true;

    log('initialized (history + export V2)');
    loadRunsHistory();
    ensureExportToolbar();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    setTimeout(init, 0);
  }

  window.vspReloadRuns = loadRunsHistory;

})();
JS

echo "[PATCH] Đã ghi JS mới (history + export V2, DOM fallback) vào $TARGET"
