#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT/templates/index.html"
CSS="$ROOT/static/css/security_resilient.css"

echo "[i] ROOT = $ROOT"
echo "[i] TPL  = $TPL"
echo "[i] CSS  = $CSS"

########################################
# 1) Sửa CSS: bar phẳng, không 3D
########################################
if [ -f "$CSS" ]; then
  python3 - "$CSS" <<'PY'
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
css = path.read_text(encoding="utf-8")

# Thay toàn bộ block .dash-sev-bar-inner thành style mới phẳng
new_block = """
.dash-sev-bar-inner {
  width: 40px;
  border-radius: 4px 4px 0 0;
  background: #64748b;
  box-shadow: none;
  height: 40px; /* sẽ được JS override theo tỉ lệ */
  transition: height 0.4s ease-out;
}

/* Màu phẳng cho từng mức độ */
.dash-sev-bar:nth-child(1) .dash-sev-bar-inner { background: #f97373; } /* Critical */
.dash-sev-bar:nth-child(2) .dash-sev-bar-inner { background: #fb923c; } /* High */
.dash-sev-bar:nth-child(3) .dash-sev-bar-inner { background: #eab308; } /* Medium */
.dash-sev-bar:nth-child(4) .dash-sev-bar-inner { background: #22c55e; } /* Low */
"""

pattern = re.compile(r"\.dash-sev-bar-inner\s*\{[^}]*\}(?:\s*\.dash-sev-bar:nth-child\(1\)[\s\S]*?\.dash-sev-bar:nth-child\(4\)[\s\S]*?;)?", re.MULTILINE)
if pattern.search(css):
    css = pattern.sub(new_block, css)
    print("[OK] Đã thay block .dash-sev-bar-inner bằng style bar phẳng.")
else:
    # Nếu không match, append block mới
    css += "\n\n/* DASHBOARD_CHART_STYLE_V2 */" + new_block + "\n"
    print("[WARN] Không tìm thấy block cũ, đã append style mới ở cuối file.")

path.write_text(css, encoding="utf-8")
PY
else
  echo "[WARN] Không tìm thấy $CSS – bỏ qua phần CSS."
fi

########################################
# 2) Thêm JS: scale 1 phổ + ẩn note dài + fix click
########################################
if [ -f "$TPL" ]; then
  python3 - "$TPL" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
html = path.read_text(encoding="utf-8")

marker = "/* DASHBOARD_CHART_V2 */"
if marker in html:
    print("[INFO] Script DASHBOARD_CHART_V2 đã tồn tại, bỏ qua.")
else:
    script = """
  <!-- DASHBOARD_CHART_V2 -->
  <script>
  (function () {
    function fixScanInputs() {
      var sel = 'input, button, select, textarea';
      document.querySelectorAll(sel).forEach(function (el) {
        try { el.style.pointerEvents = 'auto'; } catch (e) {}
      });
    }

    function hideLongSeverityNote() {
      var needle = "Critical / High / Medium / Low – các bucket được tính như sau";
      var nodes = document.querySelectorAll('small, p, div, span');
      nodes.forEach(function (el) {
        try {
          if (el.innerText && el.innerText.indexOf(needle) !== -1) {
            el.style.display = 'none';
          }
        } catch (e) {}
      });
    }

    function updateSeverityBars() {
      var bars = Array.prototype.slice.call(document.querySelectorAll('.dash-sev-bar'));
      if (!bars.length) return;

      // Lấy count từ text số phía trên/ dưới cột
      var counts = bars.map(function (bar) {
        var cEl = bar.querySelector('.dash-sev-count');
        if (!cEl) return 0;
        var txt = (cEl.textContent || "").trim();
        var n = parseFloat(txt);
        return isNaN(n) ? 0 : n;
      });

      var max = counts.reduce(function (m, c) { return c > m ? c : m; }, 0) || 1;
      var MAX_H = 190; // chiều cao tối đa giống ảnh 2

      bars.forEach(function (bar, idx) {
        var inner = bar.querySelector('.dash-sev-bar-inner');
        if (!inner) return;
        var count = counts[idx] || 0;
        var ratio = count / max;
        if (!isFinite(ratio) || ratio < 0) ratio = 0;
        if (ratio > 1) ratio = 1;
        var h = 10 + ratio * MAX_H;
        inner.style.height = h + "px";
      });
    }

    function initDashboardChartV2() {
      fixScanInputs();
      hideLongSeverityNote();
      updateSeverityBars();
    }

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', initDashboardChartV2);
    } else {
      initDashboardChartV2();
    }
  })();
  </script>
  /* DASHBOARD_CHART_V2 */
"""
    if "</body>" in html:
        html = html.replace("</body>", script + "\n</body>")
        print("[OK] Đã chèn script DASHBOARD_CHART_V2 trước </body>.")
    else:
        html += script
        print("[WARN] Không thấy </body>, đã append script vào cuối file.")

    path.write_text(html, encoding="utf-8")
PY
else
  echo "[ERR] Không tìm thấy $TPL"
fi

echo "[DONE] patch_dashboard_chart_style_v2.sh hoàn thành."
