#!/usr/bin/env bash
set -euo pipefail

TPL="/home/test/Data/SECURITY_BUNDLE/ui/templates/index.html"
echo "[i] TPL = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy templates/index.html"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    html = f.read()

marker_flag = "PATCH_HIDE_OLD_TREND"
if marker_flag in html:
    print("[INFO] Đã có patch JS hide old TREND, bỏ qua.")
    sys.exit(0)

if "</body>" not in html:
    print("[ERR] Không tìm thấy </body> trong index.html")
    sys.exit(1)

script = """
    <!-- PATCH_HIDE_OLD_TREND -->
    <script>
    (function () {
      function hideOldTrend() {
        try {
          var tables = Array.from(document.querySelectorAll('table'));
          var trendTables = tables.filter(function (t) {
            var ths = t.querySelectorAll('thead tr th');
            if (ths.length < 3) return false;
            var t0 = (ths[0].textContent || '').trim().toUpperCase();
            var t1 = (ths[1].textContent || '').trim().toUpperCase();
            var t2 = (ths[2].textContent || '').trim().toUpperCase();
            return t0 === 'RUN' && t1 === 'TOTAL' && t2.indexOf('CRIT') !== -1;
          });
          if (trendTables.length <= 1) return;
          trendTables.sort(function (a, b) {
            return a.getBoundingClientRect().top - b.getBoundingClientRect().top;
          });
          // Giữ bảng trend đầu tiên, ẩn các bảng trend phía dưới
          trendTables.slice(1).forEach(function (t) {
            var box = t;
            // nếu có div wrapper thì ẩn wrapper cho đẹp
            if (t.parentElement && t.parentElement.classList.contains('dash-table-wrapper')) {
              box = t.parentElement.parentElement || t.parentElement;
            }
            box.style.display = 'none';
          });
        } catch (e) {
          console.log('[PATCH_HIDE_OLD_TREND] error:', e);
        }
      }
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', hideOldTrend);
      } else {
        hideOldTrend();
      }
    })();
    </script>
"""

html = html.replace("</body>", script + "\n</body>")

with open(path, "w", encoding="utf-8") as f:
    f.write(html)

print("[OK] Đã chèn JS PATCH_HIDE_OLD_TREND vào index.html")
PY
