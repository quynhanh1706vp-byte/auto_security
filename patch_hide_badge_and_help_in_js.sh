#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
JS="$ROOT/static/data_source.js"

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

marker = "PATCH_HIDE_8_7_AND_HELP"
if marker in text:
    print("[INFO] Đã patch rồi, bỏ qua.")
    raise SystemExit

snippet = """

// PATCH_HIDE_8_7_AND_HELP
(function () {
  function hideStuff() {
    try {
      var nodes = document.querySelectorAll('*');
      var patterns = [
        'Mỗi dòng tương ứng với 1 tool',
        'tool_config.json'
      ];
      nodes.forEach(function (el) {
        if (!el || !el.textContent) return;
        var txt = el.textContent.trim();

        // Ẩn badge 
        if (txt === '') {
          if (el.parentElement) el.parentElement.style.display = 'none';
          else el.style.display = 'none';
          return;
        }

        // Ẩn đoạn mô tả Settings – Tool config
        for (var i = 0; i < patterns.length; i++) {
          if (txt.indexOf(patterns[i]) !== -1) {
            if (el.parentElement) el.parentElement.style.display = 'none';
            else el.style.display = 'none';
            break;
          }
        }
      });
    } catch (e) {
      console.log('PATCH_HIDE_8_7_AND_HELP error', e);
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

with open(path, "a", encoding="utf-8") as f:
    f.write(snippet)

print(f"[OK] Đã append PATCH_HIDE_8_7_AND_HELP vào {path}")
PY
