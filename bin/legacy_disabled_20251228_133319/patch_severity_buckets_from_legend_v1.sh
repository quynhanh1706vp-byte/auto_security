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

snippet = r"""
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
"""

if "AUTO-FIX SEVERITY BUCKET BARS FROM LEGEND" in data:
    print("[INFO] Snippet đã tồn tại, bỏ qua.")
else:
    js.write_text(data.rstrip() + "\n\n" + snippet + "\n", encoding="utf-8")
    print("[OK] Đã append snippet auto-fix severity buckets.")
PY
