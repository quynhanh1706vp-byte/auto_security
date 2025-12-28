#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
JS="$ROOT/static/patch_hide_debug_banner.js"
TPL="$ROOT/templates/index.html"

echo "[i] ROOT = $ROOT"
echo "[i] JS   = $JS"
echo "[i] TPL  = $TPL"

# 1) Tạo file JS: ẩn các phần tử chứa text debug
cat > "$JS" <<'JS'
(function () {
  function hideByTextFragment(txt) {
    try {
      var all = document.querySelectorAll('body *');
      all.forEach(function (el) {
        if (!el.textContent) return;
        if (el.textContent.indexOf(txt) !== -1) {
          el.style.display = 'none';
        }
      });
    } catch (e) {
      console.log('[DEBUG-HIDE] error:', e);
    }
  }

  function runHide() {
    hideByTextFragment('Bản DEBUG đơn giản – nếu bạn nhìn thấy dòng này là template đã chạy OK.');
    hideByTextFragment('DEBUG TEMPLATE V2');
    hideByTextFragment('Nhấn để gọi /api/run_scan_simple');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', runHide);
  } else {
    runHide();
  }
})();
JS

echo "[OK] Đã ghi $JS"

# 2) Chèn thẻ <script> vào templates/index.html trước </body>
if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys
from pathlib import Path

tpl_path = Path(sys.argv[1])
data = tpl_path.read_text(encoding="utf-8")

snippet = "  <script src=\"{{ url_for('static', filename='patch_hide_debug_banner.js') }}\"></script>\\n</body>"

if "patch_hide_debug_banner.js" in data:
    print("[INFO] Đã có script patch_hide_debug_banner.js trong template, bỏ qua chèn.")
else:
    if "</body>" not in data:
        print("[ERR] Không thấy </body> trong template, dừng.")
        sys.exit(1)
    data = data.replace("</body>", snippet)
    tpl_path.write_text(data, encoding="utf-8")
    print("[OK] Đã chèn script patch_hide_debug_banner.js trước </body>.")
PY

echo "[DONE] patch_hide_debug_banner.sh hoàn thành."
