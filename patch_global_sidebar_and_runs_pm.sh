#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
JS="$ROOT/static/patch_global_ui.js"

echo "[i] ROOT = $ROOT"
echo "[i] JS   = $JS"

########################################
# 1) Ghi file JS global
########################################
cat > "$JS" <<'JS'
(function () {
  function log(msg) {
    console.log('[GLOBAL-UI]', msg);
  }

  function norm(t) {
    return (t || '').replace(/\s+/g, ' ').trim();
  }

  // --- 1) Đổi label sidebar ---
  function patchSidebarLabels() {
    var map = {
      'Lần quét & Báo cáo': 'Run & Report',
      'Lần quét &amp; Báo cáo': 'Run &amp; Report',
      'Cấu hình tool (JSON)': 'Settings',
      'Nguồn dữ liệu': 'Data Source'
    };

    var all = Array.from(document.body.querySelectorAll('*'));
    all.forEach(function (el) {
      if (!el.childNodes || el.childNodes.length !== 1) return;
      var node = el.childNodes[0];
      if (!node.nodeType || node.nodeType !== Node.TEXT_NODE) return;

      var textRaw = node.textContent || '';
      var text = norm(textRaw);
      if (!text) return;

      Object.keys(map).forEach(function (oldLabel) {
        if (text === norm(oldLabel)) {
          node.textContent = map[oldLabel]
            .replace('&amp;', '&'); // khi gán lại textNode thì dùng '&'
        }
      });
    });
  }

  // --- 2) Thêm PM HTML / PM PDF trên trang /runs ---
  function patchRunsPage() {
    if (!/\/runs\/?$/.test(window.location.pathname)) {
      return; // chỉ chạy trên /runs
    }

    log('Patch trang /runs: thêm PM HTML / PM PDF');

    var links = Array.from(document.querySelectorAll('a'));
    links.forEach(function (a) {
      var text = norm(a.textContent || '');
      if (text !== 'Xem chi tiết') return;

      var href = a.getAttribute('href') || '';
      // thường dạng /report/RUN_.../html
      var m = href.match(/(RUN_[^/]+)/);
      if (!m) return;
      var runId = m[1];

      var cell = a.parentElement;
      if (!cell || cell.getAttribute('data-pm-links-added') === '1') return;
      cell.setAttribute('data-pm-links-added', '1');

      function makeLink(label, fmt) {
        var l = document.createElement('a');
        l.textContent = label;
        l.href = '/pm_report/' + encodeURIComponent(runId) + '/' + fmt;
        l.target = '_blank';
        l.style.marginLeft = '4px';
        return l;
      }

      cell.appendChild(document.createTextNode(' | '));
      cell.appendChild(makeLink('PM HTML', 'html'));
      cell.appendChild(document.createTextNode(' / '));
      cell.appendChild(makeLink('PM PDF', 'pdf'));
    });
  }

  function init() {
    try {
      patchSidebarLabels();
      patchRunsPage();
    } catch (e) {
      console.error('[GLOBAL-UI] Lỗi:', e);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
JS
echo "[OK] Đã ghi $JS"

########################################
# 2) Tìm template có </body> để inject script
########################################
TPL=$(grep -RIl "</body>" "$ROOT/templates" || true)

if [ -z "$TPL" ]; then
  echo "[ERR] Không tìm thấy file template nào chứa </body> trong templates/."
  exit 1
fi

echo "[i] Dùng template: $TPL"

python3 - "$TPL" <<'PY'
import sys

path = sys.argv[1]
print("[PY] Đọc", path)
with open(path, "r", encoding="utf-8") as f:
    html = f.read()

marker = "patch_global_ui.js"
if marker in html:
    print("[PY] Đã có patch_global_ui.js, bỏ qua.")
    raise SystemExit(0)

needle = "</body>"
if needle not in html:
    print("[PY][ERR] Không tìm thấy </body> trong template được chọn.")
    raise SystemExit(1)

snippet = "  <script src=\"{{ url_for('static', filename='patch_global_ui.js') }}\"></script>\\n</body>"

html = html.replace(needle, snippet)

with open(path, "w", encoding="utf-8") as f:
    f.write(html)

print("[PY] Đã chèn script patch_global_ui.js trước </body> trong", path)
PY

echo "[DONE] patch_global_sidebar_and_runs_pm.sh hoàn thành."
