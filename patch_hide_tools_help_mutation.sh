#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TPL="$ROOT/templates/index.html"

echo "[i] ROOT = $ROOT"
echo "[i] TPL  = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys

path = sys.argv[1]
html = open(path, encoding="utf-8").read()

marker = "PATCH_HIDE_TOOLS_HELP_MUTATION"
if marker in html:
    print("[INFO] Đã có PATCH_HIDE_TOOLS_HELP_MUTATION trong index.html, bỏ qua.")
    sys.exit(0)

snippet = """
<script>
// PATCH_HIDE_TOOLS_HELP_MUTATION
(function () {
  function hideBadNodes() {
    try {
      var patterns = [
        "Mỗi dòng tương ứng với 1 tool",
        "tool_config.json"
      ];
      var nodes = document.querySelectorAll("*");
      nodes.forEach(function (el) {
        if (!el || !el.textContent) return;
        var txt = el.textContent.trim();

        // Ẩn badge 
        if (txt === "") {
          if (el.parentElement) el.parentElement.style.display = "none";
          else el.style.display = "none";
          return;
        }

        // Ẩn đoạn mô tả Settings – Tool config
        for (var i = 0; i < patterns.length; i++) {
          if (txt.indexOf(patterns[i]) !== -1) {
            if (el.parentElement) el.parentElement.style.display = "none";
            else el.style.display = "none";
            break;
          }
        }
      });
    } catch (e) {
      console.log("PATCH_HIDE_TOOLS_HELP_MUTATION error", e);
    }
  }

  // Chạy ngay khi DOM sẵn sàng
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", hideBadNodes);
  } else {
    hideBadNodes();
  }

  // Theo dõi SPA: khi nội dung tab Settings được load sau này
  var obs = new MutationObserver(function () {
    hideBadNodes();
  });
  if (document.body) {
    obs.observe(document.body, { childList: true, subtree: true });
  }
})();
</script>
"""

low = html.lower()
idx = low.rfind("</body>")
if idx == -1:
    print("[ERR] Không tìm thấy </body> trong index.html")
    sys.exit(1)

new_html = html[:idx] + snippet + "\\n" + html[idx:]
with open(path, "w", encoding="utf-8") as f:
    f.write(new_html)

print("[OK] Đã chèn PATCH_HIDE_TOOLS_HELP_MUTATION vào index.html")
PY
