#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
JS="$ROOT/static/scan_status.js"

echo "[i] ROOT = $ROOT"
echo "[i] JS   = $JS"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy $JS"
  exit 1
fi

python3 - "$JS" <<'PY'
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()

marker = "PATCH_STUBBORN_HIDE"
if marker in text:
    print("[INFO] Đã patch PATCH_STUBBORN_HIDE trước đó, bỏ qua.")
    raise SystemExit

snippet = """

// PATCH_STUBBORN_HIDE
(function () {
  function hideHelpAndRatio() {
    try {
      var nodes = document.querySelectorAll('*');
      nodes.forEach(function (el) {
        if (!el || !el.textContent) return;
        var txt = el.textContent;

        // 1) Ẩn đoạn help tiếng Việt ở SETTINGS – TOOL CONFIG
        if (txt.indexOf('Mỗi dòng tương ứng với 1 tool') !== -1 ||
            txt.indexOf('/home/test/Data/SECURITY_BUNDLE/ui/tool_config.json') !== -1) {
          if (el.parentElement) {
            el.parentElement.style.display = 'none';
          } else {
            el.style.display = 'none';
          }
          return;
        }

        // 2) Xóa riêng phần "8/7" trong header Crit/High
        if (txt.indexOf('Crit/High:') !== -1 && txt.indexOf('8/7') !== -1) {
          var html = el.innerHTML || '';
          html = html.replace(/8\/7/g, '').replace(/\s{2,}/g, ' ');
          el.innerHTML = html.trim();
        }
      });
    } catch (e) {
      console.log('PATCH_STUBBORN_HIDE error', e);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', hideHelpAndRatio);
  } else {
    hideHelpAndRatio();
  }

  var obs = new MutationObserver(function () {
    hideHelpAndRatio();
  });
  if (document.body) {
    obs.observe(document.body, { childList: true, subtree: true });
  }
})();
"""

with open(path, "a", encoding="utf-8") as f:
    f.write(snippet)

print(f"[OK] Đã append PATCH_STUBBORN_HIDE vào {path}")
PY
