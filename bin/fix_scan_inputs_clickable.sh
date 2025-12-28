#!/usr/bin/env bash
set -euo pipefail

TPL="templates/index.html"
echo "[i] TPL = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
html = path.read_text(encoding="utf-8")

marker = "/* SCAN_INPUTS_CLICK_FIX */"

# Nếu đã chèn rồi thì thôi
if marker in html:
    print("[INFO] Đã có SCAN_INPUTS_CLICK_FIX trong index.html, bỏ qua.")
else:
    script = """
  <!-- SCAN_INPUTS_CLICK_FIX -->
  <script>
  (function () {
    function fixScanInputs() {
      var sel = 'input, button, select, textarea';
      document.querySelectorAll(sel).forEach(function (el) {
        try {
          el.style.pointerEvents = 'auto';
        } catch (e) {}
      });
    }
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', fixScanInputs);
    } else {
      fixScanInputs();
    }
  })();
  </script>
  /* SCAN_INPUTS_CLICK_FIX */
"""
    if "</body>" in html:
        html = html.replace("</body>", script + "\n</body>")
        print("[OK] Đã chèn SCAN_INPUTS_CLICK_FIX trước </body>.")
    else:
        html += script
        print("[WARN] Không tìm thấy </body>, append script vào cuối file.")

    path.write_text(html, encoding="utf-8")
PY
