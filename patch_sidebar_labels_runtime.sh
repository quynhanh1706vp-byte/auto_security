#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
JS="$ROOT/static/patch_sidebar_labels_runtime.js"
TPL="$ROOT/templates/index.html"

echo "[i] ROOT = $ROOT"
echo "[i] JS   = $JS"
echo "[i] TPL  = $TPL"

########################################
# 1) Tạo file JS đổi label sidebar
########################################
cat > "$JS" <<'JS'
(function () {
  function log(msg) {
    console.log('[SIDEBAR-PATCH]', msg);
  }

  function norm(t) {
    return (t || '').replace(/\s+/g, ' ').trim();
  }

  var map = {
    'Lần quét & Báo cáo': 'Run & Report',
    'Cấu hình tool (JSON)': 'Settings',
    'Nguồn dữ liệu': 'Data Source'
  };

  function patchLabels() {
    var all = Array.from(document.body.querySelectorAll('*'));

    all.forEach(function (el) {
      if (!el.childNodes || el.childNodes.length !== 1) return;
      var node = el.childNodes[0];
      if (!node.nodeType || node.nodeType !== Node.TEXT_NODE) return;

      var text = norm(node.textContent || '');
      if (!text) return;

      Object.keys(map).forEach(function (oldLabel) {
        if (text === oldLabel) {
          node.textContent = map[oldLabel];
        }
      });
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', patchLabels);
  } else {
    patchLabels();
  }
})();
JS
echo "[OK] Đã ghi $JS"

########################################
# 2) Chèn script vào templates/index.html
########################################
if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy templates/index.html"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys

path = sys.argv[1]
print("[PY] Đọc", path)
with open(path, "r", encoding="utf-8") as f:
    html = f.read()

marker = "patch_sidebar_labels_runtime.js"
if marker in html:
    print("[PY] Đã có patch_sidebar_labels_runtime.js, bỏ qua.")
    raise SystemExit(0)

needle = "</body>"
if needle not in html:
    print("[PY][ERR] Không tìm thấy </body> trong index.html")
    raise SystemExit(1)

snippet = '  <script src="{{ url_for(\'static\', filename=\'patch_sidebar_labels_runtime.js\') }}"></script>\\n</body>'

html = html.replace(needle, snippet)

with open(path, "w", encoding="utf-8") as f:
    f.write(html)

print("[PY] Đã chèn script patch_sidebar_labels_runtime.js trước </body>.")
PY

echo "[DONE] patch_sidebar_labels_runtime.sh hoàn thành."
