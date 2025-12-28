#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TPL="$ROOT/templates/index.html"

echo "[i] ROOT = $ROOT"
echo "[i] TPL  = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy templates/index.html"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys

path = sys.argv[1]
html = open(path, encoding="utf-8").read()

marker = "PATCH_DATA_TAB_LAYOUT_1_4_3_4"
if marker in html:
    print("[INFO] index.html đã có PATCH_DATA_TAB_LAYOUT_1_4_3_4, bỏ qua.")
    sys.exit(0)

snippet = """
<script>
// PATCH_DATA_TAB_LAYOUT_1_4_3_4
// Chia layout tab DATA thành 1/4 (DATA SOURCE) + 3/4 (SAMPLE FINDINGS)
(function () {
  function adjustDataTabLayout() {
    try {
      // Tìm card DATA SOURCE / JSON SUMMARY
      var dataCardHeader = Array.from(
        document.querySelectorAll('.card h1, .card h2, .card h3, .card-title, .card-header')
      ).find(function (el) {
        return el.textContent && el.textContent.indexOf('DATA SOURCE / JSON SUMMARY') !== -1;
      });

      // Tìm card SAMPLE FINDINGS
      var sampleCardHeader = Array.from(
        document.querySelectorAll('.card h1, .card h2, .card h3, .card-title, .card-header')
      ).find(function (el) {
        return el.textContent && el.textContent.indexOf('SAMPLE FINDINGS') !== -1;
      });

      function setColWidthFromHeader(headerEl, percent) {
        if (!headerEl) return;
        // ưu tiên chỉnh div "cột" bao ngoài card (thường là col-*)
        var col = headerEl.closest('[class*="col-"]');
        if (!col) {
          // fallback: chỉnh luôn card
          col = headerEl.closest('.card');
        }
        if (!col) return;

        var p = percent.toString() + '%';
        col.style.flex = '0 0 ' + p;
        col.style.maxWidth = p;
      }

      setColWidthFromHeader(dataCardHeader, 25);   // 1/4
      setColWidthFromHeader(sampleCardHeader, 75); // 3/4
    } catch (e) {
      console.log('PATCH_DATA_TAB_LAYOUT_1_4_3_4 error', e);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', adjustDataTabLayout);
  } else {
    adjustDataTabLayout();
  }

  // Theo dõi SPA, nếu tab DATA load lại thì vẫn áp dụng
  var obs = new MutationObserver(function () {
    adjustDataTabLayout();
  });
  if (document.body) {
    obs.observe(document.body, { childList: true, subtree: true });
  }
})();
</script>
"""

low = html.lower()
idx = low.rfind("</body>")
if idx == -1:
    print("[ERR] Không tìm thấy </body> trong index.html")
    sys.exit(1)

new_html = html[:idx] + snippet + "\\n" + html[idx:]
with open(path, "w", encoding="utf-8") as f:
    f.write(new_html)

print("[OK] Đã chèn PATCH_DATA_TAB_LAYOUT_1_4_3_4 vào index.html")
PY
