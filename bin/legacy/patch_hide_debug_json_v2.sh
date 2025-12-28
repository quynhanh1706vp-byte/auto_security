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

marker = "<!-- PATCH_HIDE_DEBUG_JSON_V2 -->"
if marker in html:
    print("[OK] base.html đã có PATCH_HIDE_DEBUG_JSON_V2, bỏ qua.")
else:
    js = r"""<!-- PATCH_HIDE_DEBUG_JSON_V2 -->
<script>
(function () {
  function hideByText(txt) {
    var nodes = Array.from(
      document.querySelectorAll('span,div,button,a,p,small')
    );
    nodes.forEach(function (el) {
      var t = (el.textContent || '').trim();
      if (!t) return;
      if (t === txt || t.indexOf(txt) !== -1) {
        // CHỈ ẨN CHÍNH ELEMENT CHỨA TEXT, KHÔNG ẨN CONTAINER
        el.style.display = 'none';
      }
    });
  }

  function run() {
    hideByText('Xem JSON thô (debug)');
    hideByText('Xem toàn bộ nội dung  tool_config.json');
    hideByText('TRDL / ANY-URL ready');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', run);
  } else {
    run();
  }
})();
</script>"""
    if "</body>" not in html:
        print("[ERR] Không tìm thấy </body> trong base.html")
    else:
        html = html.replace("</body>", marker + "\\n" + js + "\\n</body>")
        path.write_text(html)
        print("[OK] Đã chèn PATCH_HIDE_DEBUG_JSON_V2 vào base.html")
PY

echo "[DONE] patch_hide_debug_json_v2.sh hoàn thành."
