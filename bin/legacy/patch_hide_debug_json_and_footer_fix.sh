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
if marker not in html:
    print("[ERR] Không thấy marker PATCH_HIDE_DEBUG_JSON trong base.html")
    sys.exit(1)

start = html.index(marker)
script_open = html.find("<script>", start)
script_close = html.find("</script>", script_open)
if script_open == -1 or script_close == -1:
    print("[ERR] Không tìm thấy <script>...</script> sau marker")
    sys.exit(1)

new_block = """<!-- PATCH_HIDE_DEBUG_JSON -->
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
        el.style.display = 'none';   // CHỈ ẨN CHÍNH NÓ, KHÔNG ẨN CONTAINER
      }
    });
  }

  function run() {
    hideByText('Xem JSON thô (debug)');
    hideByText('Xem toàn bộ nội dung tool_config.json');
    hideByText('TRDL / ANY-URL ready');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', run);
  } else {
    run();
  }
})();
</script>"""

before = html[:start]
after = html[script_close + len("</script>"):]
html_new = before + new_block + after
path.write_text(html_new)

print("[OK] Đã thay PATCH_HIDE_DEBUG_JSON bằng bản fix (ẩn đúng element).")
PY

echo "[DONE] patch_hide_debug_json_and_footer_fix.sh hoàn thành."
