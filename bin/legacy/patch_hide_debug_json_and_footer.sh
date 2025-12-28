#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
BASE="$ROOT/templates/base.html"

echo "[i] ROOT = $ROOT"
echo "[i] BASE = $BASE"

if [ ! -f "$BASE" ]; then
  echo "[ERR] Không tìm thấy templates/base.html"
  exit 1
fi

python3 - "$BASE" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
html = path.read_text()

marker = "<!-- PATCH_HIDE_DEBUG_JSON -->"

if marker in html:
    print("[OK] base.html đã có PATCH_HIDE_DEBUG_JSON, bỏ qua.")
else:
    js = r"""<!-- PATCH_HIDE_DEBUG_JSON -->
<script>
(function () {
  function hideByText(txt) {
    var nodes = Array.from(document.querySelectorAll('span,div,button,a,p,small,h3,h4'));
    nodes.forEach(function (el) {
      var t = (el.textContent || '').trim();
      if (!t) return;
      if (t === txt || t.indexOf(txt) !== -1) {
        var box = el.closest('section, .card, .rounded-2xl, .rounded-xl, .rounded-lg, div');
        if (box) {
          box.style.display = 'none';
        }
      }
    });
  }

  function run() {
    hideByText('Xem JSON thô (debug)');
    hideByText('TRDL / ANY-URL ready');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', run);
  } else {
    run();
  }
})();
</script>
"""
    if "</body>" not in html:
        print("[ERR] Không tìm thấy </body> trong base.html")
    else:
        html = html.replace("</body>", marker + "\n" + js + "\n</body>")
        path.write_text(html)
        print("[OK] Đã chèn PATCH_HIDE_DEBUG_JSON vào base.html")
PY

echo "[DONE] patch_hide_debug_json_and_footer.sh hoàn thành."
