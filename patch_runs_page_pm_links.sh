#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/app.py"

echo "[i] ROOT = $ROOT"
echo "[i] APP  = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy app.py"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, os

path = sys.argv[1]
print("[PY] Đọc", path)

with open(path, "r", encoding="utf-8") as f:
    src = f.read()

changed = False

# 1) Đổi label "Lần quét & Báo cáo" -> "Run & Report" (cả bản &amp;)
for old, new in {
    "Lần quét &amp; Báo cáo": "Run &amp; Report",
    "Lần quét & Báo cáo": "Run & Report",
}.items():
    if old in src:
        src = src.replace(old, new)
        print(f"[PY] Thay '{old}' -> '{new}'")
        changed = True

marker = "PATCH_RUNS_SIMPLE_PM_V1"
if marker in src:
    print("[PY] Đã có marker PM trên trang /runs, bỏ qua chèn JS.")
else:
    needle = "Danh sách RUN trong thư mục out/"
    idx = src.find(needle)
    if idx == -1:
        print("[PY][WARN] Không tìm thấy text 'Danh sách RUN trong thư mục out/' trong app.py → không biết block HTML /runs để chèn.")
    else:
        # Làm việc trên phần từ needle trở về sau, để chèn JS trước </body> của trang /runs
        tail = src[idx:]
        end_body = tail.find("</body>")
        if end_body == -1:
            print("[PY][WARN] Không tìm thấy </body> sau đoạn /runs, không chèn JS được.")
        else:
            js_snippet = """
<script>
// PATCH_RUNS_SIMPLE_PM_V1
(function () {
  function norm(t) {
    return (t || '').replace(/\\s+/g, ' ').trim();
  }
  function patch() {
    var links = Array.from(document.querySelectorAll('a'));
    links.forEach(function (a) {
      if (norm(a.textContent || '') !== 'Xem chi tiết') return;

      var href = a.getAttribute('href') || '';
      // lấy RUN_* từ href, ví dụ /report/RUN_2025.../html
      var m = href.match(/(RUN_[^/]+)/);
      if (!m) return;
      var runId = m[1];

      var cell = a.parentElement;
      if (!cell || cell.getAttribute('data-pm-links-added') === '1') return;
      cell.setAttribute('data-pm-links-added', '1');

      function mk(label, fmt) {
        var link = document.createElement('a');
        link.textContent = label;
        link.href = '/pm_report/' + encodeURIComponent(runId) + '/' + fmt;
        link.target = '_blank';
        link.style.marginLeft = '4px';
        return link;
      }

      // thêm: " | PM HTML / PM PDF"
      cell.appendChild(document.createTextNode(' | '));
      cell.appendChild(mk('PM HTML', 'html'));
      cell.appendChild(document.createTextNode(' / '));
      cell.appendChild(mk('PM PDF', 'pdf'));
    });
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', patch);
  } else {
    patch();
  }
})();
</script>
</body>"""

            tail_new = tail.replace("</body>", js_snippet, 1)
            src = src[:idx] + tail_new
            changed = True
            print("[PY] Đã chèn JS PM HTML/PDF vào block /runs.")

if changed:
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print("[PY] Đã ghi lại app.py")
else:
    print("[PY] Không có thay đổi nào trong app.py")
PY

echo "[DONE] patch_runs_page_pm_links.sh hoàn thành."
