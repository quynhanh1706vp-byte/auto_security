#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TPL="$ROOT/templates/index.html"
JS="$ROOT/static/patch_hide_run_ui_help.js"

echo "[i] ROOT = $ROOT"
echo "[i] TPL  = $TPL"
echo "[i] JS   = $JS"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

########################################
# 1) Tạo JS ẩn các đoạn text help/debug
########################################
cat > "$JS" <<'JS'
(function () {
  function hideRunHelp() {
    try {
      var texts = [
        'Khung này dùng để nhập và lưu lại cấu hình RUN trên UI',
        'Khung này dùng để nhập thông tin RUN và bấm Run scan',
        'Panel này chỉ dùng để ghi nhớ thông tin RUN trên UI',
        'Lưu cấu hình hiển thị'
      ];

      var nodes = Array.from(document.querySelectorAll('div, p, span, button, label'));

      nodes.forEach(function (el) {
        if (!el || !el.textContent) return;
        var t = el.textContent.replace(/\s+/g, ' ').trim();
        texts.forEach(function (needle) {
          if (!needle) return;
          if (t.indexOf(needle) !== -1) {
            // Ẩn đúng element chứa text đó (không đụng vào form RUN)
            el.style.display = 'none';
          }
        });
      });
    } catch (e) {
      console.warn('[SB-HIDE-RUN-HELP] error', e);
    }
  }

  document.addEventListener('DOMContentLoaded', hideRunHelp);
})();
JS

echo "[OK] Đã ghi $JS"

########################################
# 2) Gắn script vào templates/index.html
########################################
python3 - "$TPL" <<'PY'
from pathlib import Path

path = Path("templates/index.html")
data = path.read_text(encoding="utf-8")
old = data

marker = "patch_hide_run_ui_help.js"
if marker not in data:
    inject = '\n  <script src="/static/patch_hide_run_ui_help.js?v=20251124_145000"></script>\n'
    pos = data.rfind("</body>")
    if pos != -1:
        data = data[:pos] + inject + data[pos:]
        print("[OK] Đã chèn script patch_hide_run_ui_help.js trước </body>.")
    else:
        print("[WARN] Không tìm thấy </body> để chèn script.")

if data != old:
    path.write_text(data, encoding="utf-8")
    print("[OK] Đã cập nhật templates/index.html.")
else:
    print("[INFO] templates/index.html không thay đổi (có thể đã được patch trước).")
PY

echo "[DONE] hide_run_ui_help_text.sh hoàn thành."
