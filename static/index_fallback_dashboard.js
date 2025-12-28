/**
 * Đơn giản: đọc /static/last_summary_unified.json
 * → fill Dashboard (KPI + bar chart + top risk + trend 1 dòng).
 */

function setText(id, value) {
  var el = document.getElementById(id);
  if (el) el.textContent = String(value);
}

function renderSeverityBars(stats) {
  var max = Math.max(stats.critical, stats.high, stats.medium, stats.low, 1);

  var mapping = [
    { id: "bar-critical", value: stats.critical },
    { id: "bar-high",     value: stats.high },
    { id: "bar-medium",   value: stats.medium },
    { id: "bar-low",      value: stats.low }
  ];

  mapping.forEach(function (m) {
    var col = document.getElementById(m.id);
    if (!col) return;
    var inner = col.querySelector(".sb-bar-inner");
    var valueLabel = col.querySelector(".sb-bar-value");

    var h = (m.value / max) * 100;
    col.style.height = Math.max(10, h) + "%";

    if (inner) {
      // (inner đã có gradient trong CSS, chỉ cần chiều cao của container)
    }
    if (valueLabel) {
      valueLabel.textContent = m.value;
    }
  });
}

function renderTopRiskLine(stats) {
  var p = document.getElementById("top-risk-summary");
  if (!p) return;

  if (stats.critical === 0 && stats.high === 0) {
    p.textContent =
      "Không có Critical. " +
      stats.high + " High, " +
      stats.medium + " Medium, " +
      stats.low + " Low.";
  } else {
    p.textContent =
      "Critical: " + stats.critical +
      ", High: " + stats.high +
      ", Medium: " + stats.medium +
      ", Low: " + stats.low + ".";
  }
}

function renderTrendRow(info) {
  var tbody = document.getElementById("trend-tbody");
  if (!tbody) return;
  tbody.innerHTML = "";

  var tr = document.createElement("tr");
  tr.innerHTML =
    "<td>" + (info.run_id || "—") + "</td>" +
    '<td class="align-right">' + info.total + "</td>" +
    '<td class="align-right">' + info.critical + "/" + info.high + "</td>" +
    '<td class="align-right">0</td>';

  tbody.appendChild(tr);
}

async function loadDashboard() {
  var errEl = document.getElementById("dashboard-error");
  if (errEl) errEl.textContent = "";

  try {
    var url = "/static/last_summary_unified.json?ts=" + Date.now();
    var resp = await fetch(url);
    if (!resp.ok) {
      throw new Error("HTTP " + resp.status);
    }
    var data = await resp.json();

    var total   = data.total   || 0;
    var crit    = data.critical || 0;
    var high    = data.high    || 0;
    var medium  = data.medium  || 0;
    var low     = data.low     || 0;
    var runId   = data.run_id  || "";
    var updated = data.last_updated || data.run_mtime || "";

    setText("kpi-total", total);
    setText("kpi-critical", crit);
    setText("kpi-high", high);
    setText("kpi-last-updated", updated || "—");
    setText("kpi-run-id", runId ? runId : "RUN folder mtime");

    renderSeverityBars({
      critical: crit,
      high: high,
      medium: medium,
      low: low
    });

    renderTopRiskLine({
      critical: crit,
      high: high,
      medium: medium,
      low: low
    });

    renderTrendRow({
      run_id: runId,
      total: total,
      critical: crit,
      high: high
    });
  } catch (e) {
    console.error("[DASHBOARD] load error:", e);
    if (errEl) {
      errEl.textContent =
        "Không đọc được last_summary_unified.json – kiểm tra RUN gần nhất và script build summary_unified.";
    }
  }
}

document.addEventListener("DOMContentLoaded", function () {
  loadDashboard();
});


// === AUTO-FIX SEVERITY BUCKET BARS FROM LEGEND ===
(function() {
  function sbUpdateSeverityBucketsFromLegend() {
    try {
      // Phần text dưới card: "C=0, H=170, M=8891, L=10"
      const legend = document.querySelector('.sb-severity-legend, .sb-bucket-summary');
      if (!legend) return;
      const text = legend.textContent || '';
      const m = text.match(/C=(\d+),\s*H=(\d+),\s*M=(\d+),\s*L=(\d+)/);
      if (!m) return;

      const c   = parseInt(m[1] || '0', 10) || 0;
      const h   = parseInt(m[2] || '0', 10) || 0;
      const med = parseInt(m[3] || '0', 10) || 0;
      const l   = parseInt(m[4] || '0', 10) || 0;
      const total = c + h + med + l;
      if (!total) return;

      const buckets = [
        { sel: '.sb-bar-critical, .sb-bucket-fill-critical', value: c },
        { sel: '.sb-bar-high, .sb-bucket-fill-high',         value: h },
        { sel: '.sb-bar-medium, .sb-bucket-fill-medium',     value: med },
        { sel: '.sb-bar-low, .sb-bucket-fill-low',           value: l },
      ];

      buckets.forEach(({ sel, value }) => {
        const el = document.querySelector(sel);
        if (!el) return;
        const pct = Math.max(0, Math.min(100, (value * 100.0) / total));
        el.style.width = pct + '%';
      });
    } catch (e) {
      console.warn('[SB] severity buckets auto-fix error:', e);
    }
  }

  // Gọi sau khi trang load để chắc chắn legend đã fill xong
  window.addEventListener('load', function() {
    setTimeout(sbUpdateSeverityBucketsFromLegend, 200);
  });
})();


// === SB_SEVERITY_CHART_V2 – vertical severity chart từ dòng 'C=..., H=..., M=..., L=...' ===
(function() {
  function injectSeverityChartStyles() {
    if (document.getElementById('sb-severity-chart-v2-style')) return;
    const style = document.createElement('style');
    style.id = 'sb-severity-chart-v2-style';
    style.textContent = `
      .sb-severity-chart-v2 {
        display: flex;
        align-items: flex-end;
        justify-content: space-between;
        height: 140px;
        margin-top: 8px;
        padding: 4px 4px 2px 4px;
      }
      .sb-sev-col-v2 {
        flex: 1;
        text-align: center;
        font-size: 11px;
        color: rgba(255,255,255,0.75);
      }
      .sb-sev-col-v2:not(:last-child) {
        margin-right: 4px;
      }
      .sb-sev-bar-v2 {
        width: 55%;
        margin: 0 auto 4px auto;
        border-radius: 4px 4px 0 0;
        background: #444;
        transition: height 0.25s ease-out, opacity 0.25s ease-out;
        opacity: .9;
      }
      .sb-sev-bar-critical-v2 { background: #ff4d4f; }
      .sb-sev-bar-high-v2     { background: #fa8c16; }
      .sb-sev-bar-medium-v2   { background: #fadb14; }
      .sb-sev-bar-low-v2      { background: #52c41a; }
      .sb-sev-label-v2 {
        text-transform: uppercase;
        font-size: 10px;
        opacity: .7;
      }
      .sb-sev-count-v2 {
        font-size: 11px;
        opacity: .85;
      }
    `;
    document.head.appendChild(style);
  }

  function findBucketsCard() {
    // Tìm heading có chữ "SEVERITY BUCKETS"
    const headers = Array.from(document.querySelectorAll('.sb-card-title, h3, h4, .card-title, .sb-panel-title'));
    for (const h of headers) {
      if ((h.textContent || '').toUpperCase().includes('SEVERITY BUCKETS')) {
        return h.closest('.sb-card, .card, .panel, .sb-block') || h.parentElement;
      }
    }
    return null;
  }

  function parseLegend() {
    // Tìm dòng text: "C=0, H=170, M=8891, L=10"
    const all = Array.from(document.querySelectorAll('*'));
    for (const el of all) {
      const t = (el.textContent || '').trim();
      if (!t) continue;
      if (t.includes('C=') && t.includes('H=') && t.includes('M=') && t.includes('L=')) {
        const m = t.match(/C=(\d+),\s*H=(\d+),\s*M=(\d+),\s*L=(\d+)/);
        if (m) {
          return {
            C: parseInt(m[1] || '0', 10) || 0,
            H: parseInt(m[2] || '0', 10) || 0,
            M: parseInt(m[3] || '0', 10) || 0,
            L: parseInt(m[4] || '0', 10) || 0
          };
        }
      }
    }
    return null;
  }

  function buildChart(counts) {
    injectSeverityChartStyles();
    const card = findBucketsCard();
    if (!card) return;

    // Nếu đã có chart rồi thì clear để vẽ lại
    let chart = card.querySelector('.sb-severity-chart-v2');
    if (!chart) {
      chart = document.createElement('div');
      chart.className = 'sb-severity-chart-v2';
      // chèn chart ngay phía trên dòng legend (nếu tìm được)
      const legend = (() => {
        const all = Array.from(card.querySelectorAll('*'));
        return all.find(el => (el.textContent || '').includes('C=') && (el.textContent || '').includes('H=')
                              && (el.textContent || '').includes('M=') && (el.textContent || '').includes('L='));
      })();
      if (legend && legend.parentElement === card) {
        card.insertBefore(chart, legend);
      } else {
        card.appendChild(chart);
      }
    } else {
      chart.innerHTML = '';
    }

    const C = counts.C || 0;
    const H = counts.H || 0;
    const M = counts.M || 0;
    const L = counts.L || 0;
    const max = Math.max(C, H, M, L, 1);

    const items = [
      { key: 'C', label: 'CRITICAL', value: C, barClass: 'sb-sev-bar-critical-v2' },
      { key: 'H', label: 'HIGH',     value: H, barClass: 'sb-sev-bar-high-v2'     },
      { key: 'M', label: 'MEDIUM',   value: M, barClass: 'sb-sev-bar-medium-v2'   },
      { key: 'L', label: 'LOW',      value: L, barClass: 'sb-sev-bar-low-v2'      },
    ];

    items.forEach(item => {
      const col = document.createElement('div');
      col.className = 'sb-sev-col-v2';

      const bar = document.createElement('div');
      bar.className = 'sb-sev-bar-v2 ' + item.barClass;

      let pct = (item.value * 100.0) / max;
      if (item.value > 0 && pct < 10) pct = 10; // có tí chiều cao cho giá trị nhỏ
      bar.style.height = pct + '%';

      const lbl = document.createElement('div');
      lbl.className = 'sb-sev-label-v2';
      lbl.textContent = item.label;

      const cnt = document.createElement('div');
      cnt.className = 'sb-sev-count-v2';
      cnt.textContent = String(item.value);

      col.appendChild(bar);
      col.appendChild(lbl);
      col.appendChild(cnt);
      chart.appendChild(col);
    });
  }

  function initSeverityChart() {
    try {
      const counts = parseLegend();
      if (!counts) {
        // chưa load xong legend, thử lại sau 300ms
        setTimeout(initSeverityChart, 300);
        return;
      }
      buildChart(counts);
    } catch (e) {
      console.warn('[SB] severity chart v2 error:', e);
    }
  }

  window.addEventListener('load', function() {
    setTimeout(initSeverityChart, 250);
  });
})();


// === SB_SEVERITY_CHART_V4 – vertical severity chart từ dòng 'C=..., H=..., M=..., L=...' ===
(function() {
  function sbv4InjectStyles() {
    if (document.getElementById('sbv4-severity-style')) return;
    const style = document.createElement('style');
    style.id = 'sbv4-severity-style';
    style.textContent = `
      .sbv4-severity-chart {
        display: flex;
        align-items: flex-end;
        justify-content: space-between;
        height: 140px;
        margin-top: 6px;
        padding: 4px 4px 2px 4px;
      }
      .sbv4-col {
        flex: 1;
        text-align: center;
        font-size: 11px;
        color: rgba(255,255,255,0.8);
      }
      .sbv4-col:not(:last-child) {
        margin-right: 6px;
      }
      .sbv4-bar {
        width: 55%;
        margin: 0 auto 4px auto;
        border-radius: 4px 4px 0 0;
        background: #444;
        opacity: .95;
        transition: height .25s ease-out, opacity .25s ease-out;
      }
      .sbv4-bar-critical { background: #ff4d4f; }
      .sbv4-bar-high     { background: #fa8c16; }
      .sbv4-bar-medium   { background: #fadb14; }
      .sbv4-bar-low      { background: #52c41a; }
      .sbv4-label {
        text-transform: uppercase;
        font-size: 10px;
        opacity: .7;
      }
      .sbv4-count {
        font-size: 11px;
        opacity: .9;
      }
    `;
    document.head.appendChild(style);
  }

  function sbv4ParseLegend() {
    // Tìm text kiểu: "C=0, H=170, M=8891, L=10"
    const all = Array.from(document.querySelectorAll('*'));
    for (const el of all) {
      const t = (el.textContent || '').trim();
      if (!t) continue;
      if (t.includes('C=') && t.includes('H=') && t.includes('M=') && t.includes('L=')) {
        const m = t.match(/C=(\d+),\s*H=(\d+),\s*M=(\d+),\s*L=(\d+)/);
        if (m) {
          return {
            C: parseInt(m[1] || '0', 10) || 0,
            H: parseInt(m[2] || '0', 10) || 0,
            M: parseInt(m[3] || '0', 10) || 0,
            L: parseInt(m[4] || '0', 10) || 0
          };
        }
      }
    }
    return null;
  }

  function sbv4FindBucketsCard() {
    // Tìm card có chữ SEVERITY BUCKETS
    const headers = Array.from(document.querySelectorAll('.sb-card-title, h3, h4, .card-title, .sb-panel-title'));
    for (const h of headers) {
      const txt = (h.textContent || '').toUpperCase();
      if (txt.includes('SEVERITY BUCKETS')) {
        return h.closest('.sb-card, .card, .panel, .sb-block') || h.parentElement;
      }
    }
    return null;
  }

  function sbv4RenderChart() {
    try {
      const counts = sbv4ParseLegend();
      if (!counts) {
        setTimeout(sbv4RenderChart, 300);
        return;
      }
      const card = sbv4FindBucketsCard();
      if (!card) {
        setTimeout(sbv4RenderChart, 300);
        return;
      }

      sbv4InjectStyles();

      // tạo container riêng trong card (nếu chưa có)
      let container = card.querySelector('.sbv4-severity-chart');
      if (!container) {
        container = document.createElement('div');
        container.className = 'sbv4-severity-chart';
        card.appendChild(container);
      } else {
        container.innerHTML = '';
      }

      const C = counts.C || 0;
      const H = counts.H || 0;
      const M = counts.M || 0;
      const L = counts.L || 0;
      const max = Math.max(C, H, M, L, 1);

      const items = [
        { key: 'C', label: 'CRITICAL', value: C, cls: 'sbv4-bar-critical' },
        { key: 'H', label: 'HIGH',     value: H, cls: 'sbv4-bar-high'     },
        { key: 'M', label: 'MEDIUM',   value: M, cls: 'sbv4-bar-medium'   },
        { key: 'L', label: 'LOW',      value: L, cls: 'sbv4-bar-low'      },
      ];

      items.forEach(item => {
        const col = document.createElement('div');
        col.className = 'sbv4-col';

        const bar = document.createElement('div');
        bar.className = 'sbv4-bar ' + item.cls;

        let pct = (item.value * 100.0) / max;
        if (item.value > 0 && pct < 12) pct = 12; // có chút chiều cao tối thiểu
        bar.style.height = pct + '%';

        const lbl = document.createElement('div');
        lbl.className = 'sbv4-label';
        lbl.textContent = item.label;

        const cnt = document.createElement('div');
        cnt.className = 'sbv4-count';
        cnt.textContent = String(item.value);

        col.appendChild(bar);
        col.appendChild(lbl);
        col.appendChild(cnt);
        container.appendChild(col);
      });
    } catch (e) {
      console.warn('[SB] severity chart v4 error:', e);
    }
  }

  window.addEventListener('load', function() {
    setTimeout(sbv4RenderChart, 250);
  });
})();

