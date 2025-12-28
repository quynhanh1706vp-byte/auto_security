#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/index_fallback_dashboard.js"

if [[ ! -f "$JS" ]]; then
  echo "[ERR] Không tìm thấy $JS" >&2
  exit 1
fi

python3 - << 'PY'
from pathlib import Path

js = Path("static/index_fallback_dashboard.js")
data = js.read_text(encoding="utf-8")
before = data

marker = "SB_SEVERITY_CHART_V2"
if marker in data:
    print("[INFO] Snippet SB_SEVERITY_CHART_V2 đã tồn tại, bỏ qua.")
else:
    snippet = r"""
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
"""
    js.write_text(data.rstrip() + "\n\n" + snippet + "\n", encoding="utf-8")
    print("[OK] Đã append snippet SB_SEVERITY_CHART_V2 vào static/index_fallback_dashboard.js")
PY
