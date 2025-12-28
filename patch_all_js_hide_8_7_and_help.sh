#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
STATIC_DIR="$ROOT/static"

echo "[i] ROOT       = $ROOT"
echo "[i] STATIC_DIR = $STATIC_DIR"

if [ ! -d "$STATIC_DIR" ]; then
  echo "[ERR] Không thấy thư mục static/"
  exit 1
fi

JS_FILES=$(ls "$STATIC_DIR"/*.js 2>/dev/null || true)
if [ -z "$JS_FILES" ]; then
  echo "[ERR] Không tìm thấy file .js nào trong static/"
  exit 1
fi

echo "[i] Sẽ patch các file JS:"
echo "$JS_FILES"

python3 - <<'PY'
import sys, os

root = "/home/test/Data/SECURITY_BUNDLE/ui/static"
marker = "PATCH_GLOBAL_HIDE_8_7_AND_HELP"

snippet = r"""

// PATCH_GLOBAL_HIDE_8_7_AND_HELP
(function () {
  function hideStuff() {
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
          html = html.split('8/7').join('');      // bỏ mọi "8/7"
          html = html.replace(/\s{2,}/g, ' ');    // gom bớt khoảng trắng
          el.innerHTML = html.trim();
        }
      });
    } catch (e) {
      console.log('PATCH_GLOBAL_HIDE_8_7_AND_HELP error', e);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', hideStuff);
  } else {
    hideStuff();
  }

  var obs = new MutationObserver(function () {
    hideStuff();
  });
  if (document.body) {
    obs.observe(document.body, { childList: true, subtree: true });
  }
})();
"""

for name in os.listdir(root):
    if not name.endswith(".js"):
        continue
    path = os.path.join(root, name)
    try:
        text = open(path, encoding="utf-8").read()
    except Exception:
        continue

    if marker in text:
        print(f"[INFO] {path}: đã có PATCH_GLOBAL_HIDE_8_7_AND_HELP, bỏ qua.")
        continue

    with open(path, "a", encoding="utf-8") as f:
        f.write(snippet)

    print(f"[OK] Đã append PATCH_GLOBAL_HIDE_8_7_AND_HELP vào {path}")
PY
