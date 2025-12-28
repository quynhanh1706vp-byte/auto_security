#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

# 1) Tạo file JS patch
cat > static/patch_sb_severity_chart.js << 'JS'
/**
 * patch_sb_severity_chart.js
 * Vẽ biểu đồ cột đứng cho SEVERITY BUCKETS từ dòng "C=0, H=170, M=8891, L=10".
 */
(function() {
  function injectStyles() {
    if (document.getElementById('sbv_patch_sev_style')) return;
    const style = document.createElement('style');
    style.id = 'sbv_patch_sev_style';
    style.textContent = `
      .sbv-severity-chart {
        display: flex;
        align-items: flex-end;
        justify-content: space-between;
        height: 140px;
        margin-top: 6px;
        padding: 4px 4px 2px 4px;
      }
      .sbv-sev-col {
        flex: 1;
        text-align: center;
        font-size: 11px;
        color: rgba(255,255,255,0.8);
      }
      .sbv-sev-col:not(:last-child) {
        margin-right: 6px;
      }
      .sbv-sev-bar {
        width: 55%;
        margin: 0 auto 4px auto;
        border-radius: 4px 4px 0 0;
        background: #444;
        opacity: .95;
        transition: height .25s ease-out, opacity .25s ease-out;
      }
      .sbv-sev-bar-critical { background: #ff4d4f; }
      .sbv-sev-bar-high     { background: #fa8c16; }
      .sbv-sev-bar-medium   { background: #fadb14; }
      .sbv-sev-bar-low      { background: #52c41a; }
      .sbv-sev-label {
        text-transform: uppercase;
        font-size: 10px;
        opacity: .7;
      }
      .sbv-sev-count {
        font-size: 11px;
        opacity: .9;
      }
    `;
    document.head.appendChild(style);
  }

  function parseLegend() {
    // Tìm đoạn text: "C=0, H=170, M=8891, L=10"
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

  function findBucketsCard() {
    // Tìm card có chữ "SEVERITY BUCKETS"
    const headers = Array.from(document.querySelectorAll('.sb-card-title, h3, h4, .card-title, .sb-panel-title'));
    for (const h of headers) {
      const txt = (h.textContent || '').toUpperCase();
      if (txt.includes('SEVERITY BUCKETS')) {
        return h.closest('.sb-card, .card, .panel, .sb-block') || h.parentElement;
      }
    }
    return null;
  }

  function renderChart() {
    try {
      const counts = parseLegend();
      if (!counts) {
        setTimeout(renderChart, 300);
        return;
      }
      const card = findBucketsCard();
      if (!card) {
        setTimeout(renderChart, 300);
        return;
      }

      injectStyles();

      // Tạo container trong card nếu chưa có
      let container = card.querySelector('.sbv-severity-chart');
      if (!container) {
        container = document.createElement('div');
        container.className = 'sbv-severity-chart';
        // đặt chart ngay TRÊN dòng "C=0, H=..., M=..., L=..."
        const all = Array.from(card.querySelectorAll('*'));
        const legend = all.find(el => {
          const t = (el.textContent || '');
          return t.includes('C=') && t.includes('H=') && t.includes('M=') && t.includes('L=');
        });
        if (legend && legend.parentElement === card) {
          card.insertBefore(container, legend);
        } else {
          card.appendChild(container);
        }
      } else {
        container.innerHTML = '';
      }

      const C = counts.C || 0;
      const H = counts.H || 0;
      const M = counts.M || 0;
      const L = counts.L || 0;
      const max = Math.max(C, H, M, L, 1);

      const items = [
        { label: 'CRITICAL', value: C, cls: 'sbv-sev-bar-critical' },
        { label: 'HIGH',     value: H, cls: 'sbv-sev-bar-high'     },
        { label: 'MEDIUM',   value: M, cls: 'sbv-sev-bar-medium'   },
        { label: 'LOW',      value: L, cls: 'sbv-sev-bar-low'      },
      ];

      items.forEach(item => {
        const col = document.createElement('div');
        col.className = 'sbv-sev-col';

        const bar = document.createElement('div');
        bar.className = 'sbv-sev-bar ' + item.cls;

        let pct = (item.value * 100.0) / max;
        if (item.value > 0 && pct < 12) pct = 12; // có chiều cao tối thiểu
        bar.style.height = pct + '%';

        const lbl = document.createElement('div');
        lbl.className = 'sbv-sev-label';
        lbl.textContent = item.label;

        const cnt = document.createElement('div');
        cnt.className = 'sbv-sev-count';
        cnt.textContent = String(item.value);

        col.appendChild(bar);
        col.appendChild(lbl);
        col.appendChild(cnt);
        container.appendChild(col);
      });
    } catch (e) {
      console.warn('[SB][patch_severity_chart] error:', e);
    }
  }

  window.addEventListener('load', function() {
    setTimeout(renderChart, 300);
  });
})();
JS

echo "[OK] Đã tạo static/patch_sb_severity_chart.js"

# 2) Thêm thẻ <script> vào templates/base.html (nếu chưa có)
python3 - << 'PY'
from pathlib import Path

path = Path("templates/base.html")
data = path.read_text(encoding="utf-8")

if "patch_sb_severity_chart.js" in data:
    print("[INFO] base.html đã include patch_sb_severity_chart.js, bỏ qua.")
else:
    line = '    <script src="{{ url_for(\'static\', filename=\'patch_sb_severity_chart.js\') }}"></script>\\n'

    if "patch_hide_debug_banner.js" in data:
        # chèn ngay sau patch_hide_debug_banner.js nếu có
        marker = "patch_hide_debug_banner.js"
        idx = data.find(marker)
        nl = data.find("\\n", idx)
        if nl == -1:
            nl = idx + len(marker)
        new_data = data[:nl+1] + line + data[nl+1:]
        data = new_data
        print("[OK] Đã chèn script patch_sb_severity_chart.js sau patch_hide_debug_banner.js")
    else:
        # fallback: chèn trước </body>
        idx = data.lower().rfind("</body>")
        if idx == -1:
            print("[WARN] Không tìm thấy </body> trong base.html – không chèn được script.")
        else:
            new_data = data[:idx] + line + data[idx:]
            data = new_data
            print("[OK] Đã chèn script patch_sb_severity_chart.js trước </body>")

    path.write_text(data, encoding="utf-8")
PY

echo "[DONE] enable_sb_severity_chart_patch.sh hoàn thành."
