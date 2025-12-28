#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
JS="$ROOT/static/tool_config.js"

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

marker = "PATCH_HIDE_CRIT_8_7_AND_HELP"
if marker in text:
    print("[INFO] Đã patch trước đó, bỏ qua.")
    raise SystemExit

snippet = """

// PATCH_HIDE_CRIT_8_7_AND_HELP
(function () {
  function patchSettingsHeaderAndHelp() {
    try {
      var nodes = document.querySelectorAll('*');
      nodes.forEach(function (el) {
        if (!el || !el.textContent) return;
        var txt = el.textContent;

        // 1) Ẩn đoạn mô tả tiếng Việt dưới SETTINGS – TOOL CONFIG
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
          // xóa 8/7 trong HTML, rồi dọn bớt khoảng trắng
          var html = el.innerHTML || '';
          html = html.replace(/8\/7/g, '').replace(/\s{2,}/g, ' ');
          el.innerHTML = html.trim();
        }
      });
    } catch (e) {
      console.log('PATCH_HIDE_CRIT_8_7_AND_HELP error', e);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', patchSettingsHeaderAndHelp);
  } else {
    patchSettingsHeaderAndHelp();
  }

  // Theo dõi SPA/tab load lại
  var obs = new MutationObserver(function () {
    patchSettingsHeaderAndHelp();
  });
  if (document.body) {
    obs.observe(document.body, { childList: true, subtree: true });
  }
})();
"""

with open(path, "a", encoding="utf-8") as f:
    f.write(snippet)

print(f"[OK] Đã append PATCH_HIDE_CRIT_8_7_AND_HELP vào {path}")
PY
