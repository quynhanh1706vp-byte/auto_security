#!/usr/bin/env bash
set -euo pipefail

APP_PY="/home/test/Data/SECURITY_BUNDLE/ui/app.py"

echo "[i] APP_PY = $APP_PY"

if [ ! -f "$APP_PY" ]; then
  echo "[ERR] Không tìm thấy app.py ở $APP_PY"
  exit 1
fi

python3 - "$APP_PY" <<'PY'
import sys, os

path = sys.argv[1]
text = open(path, encoding="utf-8").read()

marker = "PATCH_AFTER_RESPONSE_HIDE_HELP_8_7"
if marker in text:
    print("[INFO] app.py đã có PATCH_AFTER_RESPONSE_HIDE_HELP_8_7, bỏ qua.")
    raise SystemExit

snippet = '''

# PATCH_AFTER_RESPONSE_HIDE_HELP_8_7
@app.after_request
def patch_hide_help_and_8_7(response):
    try:
        ct = response.headers.get("Content-Type", "")
        if "text/html" not in ct:
            return response

        html = response.get_data(as_text=True)

        js = '''"<script>
// PATCH_AFTER_RESPONSE_HIDE_HELP_8_7
(function () {
  function hideStuff() {
    try {
      var nodes = document.querySelectorAll('*');
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        if (!el || !el.textContent) continue;
        var txt = el.textContent;

        // 1) Ẩn đoạn help tiếng Việt dưới SETTINGS – TOOL CONFIG
        if (txt.indexOf('Mỗi dòng tương ứng với 1 tool') !== -1 ||
            txt.indexOf('/home/test/Data/SECURITY_BUNDLE/ui/tool_config.json') !== -1) {
          if (el.parentElement) { el.parentElement.style.display = 'none'; }
          else { el.style.display = 'none'; }
          continue;
        }

        // 2) Bỏ ratio thứ 2 sau Crit/High (vd: 0/170 8/7 -> 0/170)
        if (txt.indexOf('Crit/High:') !== -1 && txt.indexOf('8/7') !== -1) {
          var idx = txt.indexOf('Crit/High:');
          var after = txt.slice(idx);
          var parts = after.split(' ');
          var ratios = [];
          for (var j = 0; j < parts.length; j++) {
            if (parts[j].indexOf('/') !== -1) {
              ratios.push(parts[j]);
            }
          }
          if (ratios.length >= 2) {
            var firstRatio = ratios[0];   // vd: 0/170
            var before = txt.slice(0, idx);
            var newTxt = before + 'Crit/High: ' + firstRatio;
            el.textContent = newTxt;
          }
        }
      }
    } catch (e) {
      console.log('PATCH_AFTER_RESPONSE_HIDE_HELP_8_7 error', e);
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
</script>"'''

        if "PATCH_AFTER_RESPONSE_HIDE_HELP_8_7" in html:
            return response

        if "</body>" in html:
            html = html.replace("</body>", js + "</body>")
            response.set_data(html)

        return response
    except Exception:
        return response

'''

# append snippet vào cuối app.py
with open(path, "a", encoding="utf-8") as f:
    f.write(snippet)

print("[OK] Đã chèn PATCH_AFTER_RESPONSE_HIDE_HELP_8_7 vào app.py")
PY
