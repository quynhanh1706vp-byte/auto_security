#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

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

marker = "SB_SEVERITY_CHART_V4"
if marker in data:
    print("[INFO] Snippet SB_SEVERITY_CHART_V4 đã tồn tại, bỏ qua.")
else:
    snippet = r"""
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
"""
    js.write_text(data.rstrip() + "\n\n" + snippet + "\n", encoding="utf-8")
    print("[OK] Đã append snippet SB_SEVERITY_CHART_V4 vào static/index_fallback_dashboard.js")
PY
