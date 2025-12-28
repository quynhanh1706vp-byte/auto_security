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

marker = "<!-- PATCH_HIDE_DEBUG_JSON_V3 -->"
if marker in html:
    print("[OK] base.html đã có PATCH_HIDE_DEBUG_JSON_V3, bỏ qua.")
else:
    js = """<!-- PATCH_HIDE_DEBUG_JSON_V3 -->
<script>
document.addEventListener('DOMContentLoaded', function () {
  var targets = [
    'Xem JSON thô (debug)',
    'tool_config.json',
    'TRDL / ANY-URL ready'
  ];
  var nodes = Array.from(document.querySelectorAll('*'));
  nodes.forEach(function (el) {
    var t = (el.textContent || '').trim();
    if (!t) return;
    for (var i = 0; i < targets.length; i++) {
      if (t.indexOf(targets[i]) !== -1) {
        el.style.display = 'none';
        break;
      }
    }
  });
});
</script>"""
    if "</body>" not in html:
        print("[ERR] Không tìm thấy </body> trong base.html")
    else:
        html = html.replace("</body>", marker + "\\n" + js + "\\n</body>")
        path.write_text(html)
        print("[OK] Đã chèn PATCH_HIDE_DEBUG_JSON_V3 vào base.html")
PY

echo "[DONE] patch_hide_debug_json_v3.sh hoàn thành."
