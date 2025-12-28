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

marker = "PATCH_FINAL_STRIP_CRIT_RATIO"
if marker in text:
    print("[INFO] Đã có PATCH_FINAL_STRIP_CRIT_RATIO trong scan_status.js, bỏ qua.")
    raise SystemExit

snippet = """

// PATCH_FINAL_STRIP_CRIT_RATIO
(function () {
  function fixHeaderAndHelp() {
    try {
      var nodes = document.querySelectorAll('*');
      nodes.forEach(function (el) {
        if (!el || !el.textContent) return;
        var txt = el.textContent;

        // 1) Ẩn đoạn help tiếng Việt dưới SETTINGS – TOOL CONFIG
        if (txt.indexOf('Mỗi dòng tương ứng với 1 tool') !== -1 ||
            txt.indexOf('/home/test/Data/SECURITY_BUNDLE/ui/tool_config.json') !== -1) {
          if (el.parentElement) {
            el.parentElement.style.display = 'none';
          } else {
            el.style.display = 'none';
          }
          return;
        }

        // 2) Bỏ ratio thứ 2 sau Crit/High (vd: 0/170 8/7 -> 0/170)
        if (txt.indexOf('Crit/High:') !== -1) {
          var idx = txt.indexOf('Crit/High:');
          var after = txt.slice(idx);           // từ "Crit/High:" trở đi
          var parts = after.split(' ');         // tách theo khoảng trắng
          var ratios = [];
          for (var i = 0; i < parts.length; i++) {
            if (parts[i].indexOf('/') !== -1) {
              ratios.push(parts[i]);
            }
          }
          if (ratios.length >= 2) {
            var firstRatio = ratios[0];         // vd "0/170"
            var before = txt.slice(0, idx);
            var newTxt = before + 'Crit/High: ' + firstRatio;
            el.textContent = newTxt;
          }
        }
      });
    } catch (e) {
      console.log('PATCH_FINAL_STRIP_CRIT_RATIO error', e);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', fixHeaderAndHelp);
  } else {
    fixHeaderAndHelp();
  }

  var obs = new MutationObserver(function () {
    fixHeaderAndHelp();
  });
  if (document.body) {
    obs.observe(document.body, { childList: true, subtree: true });
  }

  console.log('PATCH_FINAL_STRIP_CRIT_RATIO installed');
})();
"""

with open(path, "a", encoding="utf-8") as f:
    f.write(snippet)

print(f"[OK] Đã append PATCH_FINAL_STRIP_CRIT_RATIO vào", path)
PY
