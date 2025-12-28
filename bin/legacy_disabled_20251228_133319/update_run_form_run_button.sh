#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TPL="$ROOT/templates/index.html"
JS_HIDE="$ROOT/static/patch_hide_run_hint_banner.js"

echo "[i] ROOT = $ROOT"
echo "[i] TPL  = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

##############################################
# 1) Sửa nút 'Lưu cấu hình RUN (UI)' -> 'Run scan'
#    + update phần mô tả bên dưới
##############################################
python3 - "$TPL" <<'PY'
from pathlib import Path

path = Path("templates/index.html")
data = path.read_text(encoding="utf-8")
old = data

data = data.replace("Lưu cấu hình RUN (UI)", "Run scan")

data = data.replace(
    "Khung này dùng để nhập và lưu lại cấu hình RUN",
    "Khung này dùng để nhập thông tin RUN và bấm Run scan. Cấu hình vẫn được lưu lại trên trình duyệt"
)

marker = "patch_hide_run_hint_banner.js"
if marker not in data:
    inject = '\n  <script src="/static/patch_hide_run_hint_banner.js?v=20251124_142700"></script>\n'
    pos = data.rfind("</body>")
    if pos != -1:
        data = data[:pos] + inject + data[pos:]
        print("[OK] Đã chèn script patch_hide_run_hint_banner.js trước </body>.")
    else:
        print("[WARN] Không tìm thấy </body>, không chèn được script hide banner.")

if data != old:
    path.write_text(data, encoding="utf-8")
    print("[OK] Đã cập nhật templates/index.html (Run scan + mô tả).")
else:
    print("[INFO] templates/index.html không thay đổi (có thể đã patch trước đó).")
PY

##############################################
# 2) Tạo JS ẩn banner cũ 'Đang chờ chạy scan…'
##############################################
echo "[i] JS_HIDE = $JS_HIDE"

cat > "$JS_HIDE" <<'JS'
(function () {
  function hideHint() {
    try {
      var text = 'Đang chờ chạy scan…';
      var nodes = Array.from(document.querySelectorAll('div,section,span'));
      nodes.forEach(function (el) {
        if (!el || !el.textContent) return;
        if (el.textContent.indexOf(text) !== -1) {
          // Ẩn luôn nguyên block đó
          el.style.display = 'none';
        }
      });
    } catch (e) {
      console.warn('[SB-HIDE-RUN-HINT] error', e);
    }
  }
  document.addEventListener('DOMContentLoaded', hideHint);
})();
JS

echo "[OK] Đã ghi $JS_HIDE"
echo "[DONE] update_run_form_run_button.sh hoàn thành."
