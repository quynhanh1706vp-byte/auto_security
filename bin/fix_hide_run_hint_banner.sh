#!/usr/bin/env bash
set -euo pipefail

JS="static/patch_hide_run_hint_banner.js"
echo "[i] JS = $JS"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy $JS"
  exit 1
fi

python3 - "$JS" <<'PY'
from pathlib import Path

p = Path("static/patch_hide_run_hint_banner.js")
old = p.read_text(encoding="utf-8")

data = """(function () {
  function hideHint() {
    try {
      var text = 'Đang chờ chạy scan…';
      var nodes = Array.from(document.querySelectorAll('div,section,span'));

      nodes.forEach(function (el) {
        if (!el || !el.textContent) return;

        var t = el.textContent.trim();
        // phải có đúng đoạn text
        if (t.indexOf(text) === -1) return;

        // CHỐT: chỉ ẩn những block text ngắn (<= 200 ký tự)
        // để tránh ẩn luôn nguyên layout / container lớn
        if (t.length > 200) return;

        el.style.display = 'none';
      });
    } catch (e) {
      console.warn('[SB-HIDE-RUN-HINT] error', e);
    }
  }

  document.addEventListener('DOMContentLoaded', hideHint);
})();"""

if data != old:
    p.write_text(data, encoding="utf-8")
    print("[OK] Đã cập nhật patch_hide_run_hint_banner.js an toàn hơn.")
else:
    print("[INFO] patch_hide_run_hint_banner.js không thay đổi (đã đúng).")
PY

echo "[DONE] fix_hide_run_hint_banner.sh hoàn thành."
