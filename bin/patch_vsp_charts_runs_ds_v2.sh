#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS_DIR="$ROOT/static/js"
TPL="$ROOT/templates/vsp_dashboard_2025.html"

mkdir -p "$JS_DIR"

# --------------------------------------------------
# 1) Dashboard charts – pretty V3
# --------------------------------------------------
cat > "$JS_DIR/vsp_dashboard_charts_pretty_v3.js" << 'JS'
(function () {
  console.log('[VSP_CHARTS_V3] pretty charts loaded');

  if (typeof Chart === 'undefined') {
    console.warn('[VSP_CHARTS_V3] Chart.js not available, skip charts.');
    return;
  }

  var charts = {};

  function getCanvas(id) {
    var el = document.getElementById(id);
    if (!el) {
      console.warn('[VSP_CHARTS_V3] Không thấy canvas', id);
      return null;
    }
    return el.getContext('2d');
  }

  function destroyIfAny(key) {
    if (charts[key]) {
      charts[key].destroy();
      charts[key] = null;
    }
  }

  function buildSeverityDonut(dashboard) {
    var ctx = getCanvas('vsp-chart-severity');
    if (!ctx) return;

    destroyIfAny('severity');

    var sev = (dashboard && dashboard.by_severity) || {};
    var keys = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFO', 'TRACE'];
    var data = keys.map(function (k) { return sev[k] || 0; });

    charts.severity = new Chart(ctx, {
      type: 'doughnut',
      data: {
        labels: ['Critical', 'High', 'Medium', 'Low', 'Info', 'Trace'],
        datasets: [{
          data: data,
          backgroundColor: [
            '#f97373', // critical
            '#fb923c', // high
            '#facc15', // medium
            '#22c55e', // low
            '#38bdf8', // info
            '#a855f7'  // trace
          ],
          borderWidth: 0
        }]
      },
      options: {
        responsive: true,
        cutout: '65%',
        plugins: {
          legend: {
            position: 'bottom',
            labels: {
              color: '#e5e7eb',
              usePointStyle: true,
              boxWidth: 10
            }
          }
        }
      }
    });
  }

  function buildTrend(dashboard) {
    var ctx = getCanvas('vsp-chart-trend');
    if (!ctx) return;

    destroyIfAny('trend');

    var trend = (dashboard && dashboard.trend_by_run) || [];
    if (!Array.isArray(trend)) trend = [];

    // Lấy 10 run mới nhất
    var last = trend.slice(-10);
    if (!last.length) {
      last = [{ total_findings: dashboard.total_findings || 0 }];
    }

    var labels = last.map(function (_, idx) {
      return 'Run ' + (idx + 1);
    });

    var values = last.map(function (item) {
      return item.total_findings || item.total || item.findings || 0;
    });

    charts.trend = new Chart(ctx, {
      type: 'line',
      data: {
        labels: labels,
        datasets: [{
          label: 'Total findings',
          data: values,
          fill: true,
          tension: 0.4,
          borderColor: '#38bdf8',
          backgroundColor: 'rgba(56, 189, 248, 0.18)',
          borderWidth: 2,
          pointRadius: 3,
          pointHoverRadius: 4
        }]
      },
      options: {
        responsive: true,
        plugins: {
          legend: {
            display: false
          }
        },
        scales: {
          x: {
            grid: { color: 'rgba(148,163,184,0.15)' },
            ticks: { color: '#9ca3af' }
          },
          y: {
            grid: { color: 'rgba(148,163,184,0.2)' },
            ticks: { color: '#9ca3af' }
          }
        }
      }
    });
  }

  function buildByTool(dashboard) {
    var ctx = getCanvas('vsp-chart-by-tool');
    if (!ctx) return;

    destroyIfAny('byTool');

    var byTool = (dashboard && dashboard.by_tool) || [];
    if (!Array.isArray(byTool)) byTool = [];

    // Chỉ lấy top 5 tool nhiều CRITICAL + HIGH
    var mapped = byTool.map(function (t) {
      var sev = t.by_severity || {};
      var crit = sev.CRITICAL || 0;
      var high = sev.HIGH || 0;
      return {
        label: t.tool || t.name || 'N/A',
        critical: crit,
        high: high,
        total: crit + high
      };
    }).sort(function (a, b) {
      return b.total - a.total;
    }).slice(0, 5);

    if (!mapped.length) return;

    var labels = mapped.map(function (x) { return x.label; });
    var critical = mapped.map(function (x) { return x.critical; });
    var high = mapped.map(function (x) { return x.high; });

    charts.byTool = new Chart(ctx, {
      type: 'bar',
      data: {
        labels: labels,
        datasets: [
          {
            label: 'Critical',
            data: critical,
            backgroundColor: '#38bdf8'
          },
          {
            label: 'High',
            data: high,
            backgroundColor: '#fb7185'
          }
        ]
      },
      options: {
        responsive: true,
        plugins: {
          legend: {
            position: 'top',
            labels: {
              color: '#e5e7eb',
              usePointStyle: true,
              boxWidth: 10
            }
          }
        },
        scales: {
          x: {
            stacked: true,
            grid: { color: 'rgba(148,163,184,0.12)' },
            ticks: { color: '#9ca3af' }
          },
          y: {
            stacked: true,
            grid: { color: 'rgba(148,163,184,0.18)' },
            ticks: { color: '#9ca3af' }
          }
        }
      }
    });
  }

  function buildTopCwe(dashboard) {
    var ctx = getCanvas('vsp-chart-top-cwe');
    if (!ctx) return;

    destroyIfAny('topCwe');

    var list = (dashboard && dashboard.top_cwe_list) || [];
    if (!Array.isArray(list)) list = [];

    var top = list.slice(0, 8);
    if (!top.length) return;

    var labels = top.map(function (x) { return x.id || x.cwe || 'CWE'; });
    var counts = top.map(function (x) { return x.count || x.total || 0; });

    charts.topCwe = new Chart(ctx, {
      type: 'bar',
      data: {
        labels: labels,
        datasets: [{
          label: 'Findings',
          data: counts,
          backgroundColor: '#4ade80'
        }]
      },
      options: {
        indexAxis: 'y',
        responsive: true,
        plugins: {
          legend: { display: false }
        },
        scales: {
          x: {
            grid: { color: 'rgba(148,163,184,0.18)' },
            ticks: { color: '#9ca3af' }
          },
          y: {
            grid: { display: false },
            ticks: { color: '#e5e7eb' }
          }
        }
      }
    });
  }

  function updateFromDashboard(dashboard) {
    console.log('[VSP_CHARTS_V3] updateFromDashboard', dashboard);
    if (!dashboard) return;
    buildSeverityDonut(dashboard);
    buildTrend(dashboard);
    buildByTool(dashboard);
    buildTopCwe(dashboard);
  }

  // Public API + override cho bản V2
  window.VSP_DASHBOARD_CHARTS_V3 = { updateFromDashboard: updateFromDashboard };
  window.VSP_DASHBOARD_CHARTS = window.VSP_DASHBOARD_CHARTS_V3;
  window.vspDashboardChartsUpdateFromDashboard = updateFromDashboard;
})();
JS

# --------------------------------------------------
# 2) Runs & Reports – KPI + cột Reports
# --------------------------------------------------
cat > "$JS_DIR/vsp_runs_kpi_reports_v1.js" << 'JS'
(function () {
  console.log('[VSP_RUNS_KPI_V1] loaded');

  function ensureStyle() {
    if (document.getElementById('vsp-runs-kpi-style')) return;
    var s = document.createElement('style');
    s.id = 'vsp-runs-kpi-style';
    s.textContent = `
      .vsp-runs-kpi-grid {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        gap: 1rem;
        margin-bottom: 1.5rem;
      }
      .vsp-runs-kpi-card {
        background: rgba(15,23,42,0.9);
        border-radius: 0.75rem;
        padding: 0.9rem 1rem;
        border: 1px solid rgba(148,163,184,0.25);
      }
      .vsp-runs-kpi-label {
        font-size: 0.75rem;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: #9ca3af;
        margin-bottom: 0.25rem;
      }
      .vsp-runs-kpi-value {
        font-size: 1.25rem;
        font-weight: 600;
        color: #e5e7eb;
      }
      .vsp-runs-kpi-sub {
        font-size: 0.75rem;
        color: #6b7280;
        margin-top: 0.15rem;
      }
      th.vsp-runs-report-header {
        text-align: right;
      }
      td.vsp-runs-report-cell {
        text-align: right;
        white-space: nowrap;
        font-size: 0.75rem;
      }
      td.vsp-runs-report-cell a {
        color: #38bdf8;
        text-decoration: none;
        margin-left: 0.25rem;
      }
      td.vsp-runs-report-cell a:hover {
        text-decoration: underline;
      }
    `;
    document.head.appendChild(s);
  }

  function computeKpi(data) {
    var items = Array.isArray(data.items) ? data.items : [];
    var kpi = data.kpi || {};
    var totalRuns = kpi.total_runs || data.total || items.length;

    var lastN = kpi.last_n || Math.min(items.length, 10);
    var lastItems = items.slice(0, lastN);

    var done = 0, fail = 0;
    lastItems.forEach(function (r) {
      var st = (r.status || '').toUpperCase();
      if (st === 'DONE' || st === 'SUCCESS' || st === 'OK') done++;
      else if (st && st !== 'RUNNING') fail++;
    });

    var avgFindings = kpi.avg_findings_per_run_last_n;
    if (avgFindings == null && items.length) {
      var sum = items.reduce(function (acc, r) {
        return acc + (r.total_findings || r.total || 0);
      }, 0);
      avgFindings = sum / items.length;
    }

    var toolSet = new Set();
    var totalToolEntries = 0;
    items.forEach(function (r) {
      var tools = r.tools_enabled || r.tools || r.tool_list;
      if (Array.isArray(tools)) {
        totalToolEntries += tools.length;
        tools.forEach(function (t) { toolSet.add(t); });
      }
    });
    var avgToolsPerRun = items.length ? (totalToolEntries / items.length) : 0;

    return {
      totalRuns: totalRuns,
      lastN: lastN,
      doneLastN: done,
      failLastN: fail,
      avgFindings: avgFindings || 0,
      distinctTools: Array.from(toolSet),
      avgToolsPerRun: avgToolsPerRun
    };
  }

  function renderKpi(pane, k) {
    ensureStyle();
    if (!pane) return;

    var existing = document.getElementById('vsp-runs-kpi-row');
    if (existing) existing.remove();

    var wrap = document.createElement('div');
    wrap.id = 'vsp-runs-kpi-row';
    wrap.className = 'vsp-runs-kpi-grid';

    function card(label, value, sub) {
      return (
        '<div class="vsp-runs-kpi-card">' +
          '<div class="vsp-runs-kpi-label">' + label + '</div>' +
          '<div class="vsp-runs-kpi-value">' + value + '</div>' +
          (sub ? '<div class="vsp-runs-kpi-sub">' + sub + '</div>' : '') +
        '</div>'
      );
    }

    var toolsLabel = k.distinctTools.length
      ? k.distinctTools.join(', ')
      : 'N/A';

    wrap.innerHTML =
      card('Total runs', k.totalRuns, 'Tổng số lần scan đã chạy') +
      card('Last ' + k.lastN + ' runs',
           k.doneLastN + ' DONE / ' + k.failLastN + ' FAIL',
           'Trạng thái các run gần nhất') +
      card('Avg findings / run',
           Math.round(k.avgFindings).toLocaleString('en-US'),
           'Dựa trên ' + k.lastN + ' run gần nhất') +
      card('Tools per run',
           k.avgToolsPerRun ? k.avgToolsPerRun.toFixed(1) : 'N/A',
           toolsLabel);

    // chèn vào đầu pane (trước bảng)
    pane.insertBefore(wrap, pane.firstChild);
  }

  function enhanceReports(pane, data) {
    var table = pane.querySelector('table');
    if (!table) return;

    var theadRow = table.querySelector('thead tr');
    if (theadRow && !theadRow.querySelector('.vsp-runs-report-header')) {
      var th = document.createElement('th');
      th.textContent = 'Reports';
      th.className = 'vsp-runs-report-header';
      theadRow.appendChild(th);
    }

    var tbody = table.querySelector('tbody');
    if (!tbody) return;

    var items = Array.isArray(data.items) ? data.items : [];
    var rows = Array.from(tbody.rows);

    rows.forEach(function (tr, idx) {
      var item = items[idx] || {};
      var runId = item.run_id || (tr.cells[0] && tr.cells[0].textContent.trim());
      if (!runId) return;

      var td = document.createElement('td');
      td.className = 'vsp-runs-report-cell';
      td.innerHTML =
        '<a href="/api/vsp/run_export_v3?run_id=' + encodeURIComponent(runId) + '&fmt=html" target="_blank">HTML</a>' +
        '<a href="/api/vsp/run_export_v3?run_id=' + encodeURIComponent(runId) + '&fmt=pdf" target="_blank">PDF</a>' +
        '<a href="/api/vsp/run_export_v3?run_id=' + encodeURIComponent(runId) + '&fmt=zip" target="_blank">ZIP</a>';
      tr.appendChild(td);
    });
  }

  function hydrateRunsKpi() {
    var pane = document.getElementById('vsp-runs-main');
    if (!pane) {
      console.warn('[VSP_RUNS_KPI_V1] Không thấy #vsp-runs-main');
      return;
    }

    fetch('/api/vsp/runs_index_v3?limit=40')
      .then(function (r) { return r.json(); })
      .then(function (data) {
        var k = computeKpi(data);
        renderKpi(pane, k);
        enhanceReports(pane, data);
        console.log('[VSP_RUNS_KPI_V1] hydrated', k);
      })
      .catch(function (err) {
        console.error('[VSP_RUNS_KPI_V1] error', err);
      });
  }

  function onReady(fn) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', fn);
    } else {
      fn();
    }
  }

  onReady(function () {
    // chạy 1 lần; nếu sau này router thay đổi DOM, có thể gọi lại
    setTimeout(hydrateRunsKpi, 800);
  });
})();
JS

# --------------------------------------------------
# 3) Data Source – 2 mini chart (severity + by tool)
# --------------------------------------------------
cat > "$JS_DIR/vsp_datasource_mini_charts_v1.js" << 'JS'
(function () {
  console.log('[VSP_DS_MINI_CHARTS_V1] loaded');

  if (typeof Chart === 'undefined') {
    console.warn('[VSP_DS_MINI_CHARTS_V1] Chart.js not available, skip mini charts.');
    return;
  }

  var charts = {};

  function ensureStyle() {
    if (document.getElementById('vsp-ds-mini-style')) return;
    var s = document.createElement('style');
    s.id = 'vsp-ds-mini-style';
    s.textContent = `
      #vsp-ds-mini-charts {
        margin-top: 1.5rem;
        display: grid;
        grid-template-columns: minmax(0, 280px) minmax(0, 1fr);
        gap: 1.5rem;
      }
      #vsp-ds-mini-charts-card {
        grid-column: span 2 / span 2;
      }
      .vsp-ds-mini-card {
        background: rgba(15,23,42,0.9);
        border-radius: 0.75rem;
        border: 1px solid rgba(148,163,184,0.25);
        padding: 0.75rem 1rem;
      }
      .vsp-ds-mini-title {
        font-size: 0.8rem;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: #9ca3af;
        margin-bottom: 0.4rem;
      }
      .vsp-ds-mini-chart {
        width: 100%;
        height: 220px;
      }
    `;
    document.head.appendChild(s);
  }

  function aggregate(items) {
    var sev = { CRITICAL: 0, HIGH: 0, MEDIUM: 0, LOW: 0, INFO: 0, TRACE: 0 };
    var byTool = {};

    items.forEach(function (it) {
      var s = (it.severity || it.level || '').toUpperCase();
      if (!sev.hasOwnProperty(s)) {
        if (s === 'WARN' || s === 'WARNING') s = 'LOW';
        else if (s === 'ERROR') s = 'HIGH';
      }
      if (sev.hasOwnProperty(s)) sev[s]++;

      var tool = it.tool || it.source || 'N/A';
      byTool[tool] = (byTool[tool] || 0) + 1;
    });

    return { sev: sev, byTool: byTool };
  }

  function buildSevDonut(ctx, sevAgg) {
    if (charts.severity) { charts.severity.destroy(); }

    var keys = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFO', 'TRACE'];
    var data = keys.map(function (k) { return sevAgg[k] || 0; });

    charts.severity = new Chart(ctx, {
      type: 'doughnut',
      data: {
        labels: ['Critical', 'High', 'Medium', 'Low', 'Info', 'Trace'],
        datasets: [{
          data: data,
          backgroundColor: [
            '#f97373',
            '#fb923c',
            '#facc15',
            '#22c55e',
            '#38bdf8',
            '#a855f7'
          ],
          borderWidth: 0
        }]
      },
      options: {
        responsive: true,
        cutout: '60%',
        plugins: {
          legend: {
            position: 'bottom',
            labels: {
              color: '#e5e7eb',
              usePointStyle: true,
              boxWidth: 10
            }
          }
        }
      }
    });
  }

  function buildByTool(ctx, byToolMap) {
    if (charts.byTool) { charts.byTool.destroy(); }

    var entries = Object.keys(byToolMap).map(function (k) {
      return { tool: k, count: byToolMap[k] };
    }).sort(function (a, b) {
      return b.count - a.count;
    }).slice(0, 8);

    if (!entries.length) return;

    var labels = entries.map(function (x) { return x.tool; });
    var data = entries.map(function (x) { return x.count; });

    charts.byTool = new Chart(ctx, {
      type: 'bar',
      data: {
        labels: labels,
        datasets: [{
          label: 'Findings',
          data: data,
          backgroundColor: '#38bdf8'
        }]
      },
      options: {
        indexAxis: 'y',
        responsive: true,
        plugins: {
          legend: { display: false }
        },
        scales: {
          x: {
            grid: { color: 'rgba(148,163,184,0.18)' },
            ticks: { color: '#9ca3af' }
          },
          y: {
            grid: { display: false },
            ticks: { color: '#e5e7eb' }
          }
        }
      }
    });
  }

  function hydrateDs() {
    var pane = document.getElementById('vsp-datasource-main');
    if (!pane) {
      console.warn('[VSP_DS_MINI_CHARTS_V1] Không thấy #vsp-datasource-main');
      return;
    }

    fetch('/api/vsp/datasource_v2?limit=500')
      .then(function (r) { return r.json(); })
      .then(function (data) {
        var items = Array.isArray(data.items) ? data.items : data.data || [];
        if (!Array.isArray(items)) items = [];

        ensureStyle();

        var existing = document.getElementById('vsp-ds-mini-charts');
        if (existing) existing.remove();

        var wrap = document.createElement('div');
        wrap.id = 'vsp-ds-mini-charts';

        wrap.innerHTML =
          '<div class="vsp-ds-mini-card">' +
            '<div class="vsp-ds-mini-title">Severity breakdown</div>' +
            '<canvas id="vsp-ds-mini-sev" class="vsp-ds-mini-chart"></canvas>' +
          '</div>' +
          '<div class="vsp-ds-mini-card">' +
            '<div class="vsp-ds-mini-title">Findings by tool</div>' +
            '<canvas id="vsp-ds-mini-tool" class="vsp-ds-mini-chart"></canvas>' +
          '</div>';

        // chèn sau bảng data source (hoặc cuối pane)
        var table = pane.querySelector('table');
        if (table && table.parentNode) {
          table.parentNode.parentNode.insertBefore(wrap, table.parentNode.nextSibling);
        } else {
          pane.appendChild(wrap);
        }

        var agg = aggregate(items);
        var ctxSev = document.getElementById('vsp-ds-mini-sev').getContext('2d');
        var ctxTool = document.getElementById('vsp-ds-mini-tool').getContext('2d');

        buildSevDonut(ctxSev, agg.sev);
        buildByTool(ctxTool, agg.byTool);

        console.log('[VSP_DS_MINI_CHARTS_V1] hydrated mini charts');
      })
      .catch(function (err) {
        console.error('[VSP_DS_MINI_CHARTS_V1] error', err);
      });
  }

  function onReady(fn) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', fn);
    } else {
      fn();
    }
  }

  onReady(function () {
    // đợi pane + table simple V1 dựng xong rồi mới vẽ
    setTimeout(hydrateDs, 1000);
  });
})();
JS

# --------------------------------------------------
# 4) Patch template – load thêm 3 script mới sau charts_v2
# --------------------------------------------------
python - << 'PY'
from pathlib import Path
import re

tpl = Path("templates/vsp_dashboard_2025.html")
txt = tpl.read_text(encoding="utf-8")

snippet = '''
  <script src="/static/js/vsp_dashboard_charts_pretty_v3.js" defer></script>
  <script src="/static/js/vsp_runs_kpi_reports_v1.js" defer></script>
  <script src="/static/js/vsp_datasource_mini_charts_v1.js" defer></script>
'''

if "vsp_dashboard_charts_pretty_v3.js" in txt:
    print("[PATCH] Scripts V3 đã tồn tại, bỏ qua.")
else:
    pattern = r'(\\s*<script[^>]+vsp_dashboard_charts_v2.js[^>]*></script>)'
    new_txt, n = re.subn(pattern, r'\\1' + snippet, txt, count=1, flags=re.IGNORECASE)
    if n == 0:
        new_txt = txt + "\\n" + snippet
        print("[PATCH] Không tìm thấy charts_v2, đã append scripts ở cuối.")
    else:
        print("[PATCH] Đã chèn scripts V3 sau charts_v2.")
    tpl.write_text(new_txt, encoding="utf-8")
PY

echo "[DONE] patch_vsp_charts_runs_ds_v2.sh hoàn tất."
