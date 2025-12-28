#!/usr/bin/env bash
set -euo pipefail

JS="/home/test/Data/SECURITY_BUNDLE/ui/static/js/datasource_tool_rules.js"

python3 - <<'PY'
from pathlib import Path

js_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/static/js/datasource_tool_rules.js")
code = js_path.read_text(encoding="utf-8")
orig = code

snippet = """
// Hide Tool rules block on /datasource – keep only on /tool_rules
document.addEventListener("DOMContentLoaded", function () {
  try {
    if (window.location && window.location.pathname === "/datasource") {
      var sec = document.querySelector(".tool-rules-section");
      if (!sec) {
        var tbl = document.getElementById("tool-rules-table");
        if (tbl && tbl.closest) {
          sec = tbl.closest(".sb-section");
        }
      }
      if (sec && sec.parentNode) {
        sec.parentNode.removeChild(sec);
      }
    }
  } catch (e) {
    console && console.warn && console.warn("hide_tool_rules_on_datasource failed:", e);
  }
});
"""

if "Hide Tool rules block on /datasource" not in code:
    code = code.rstrip() + "\n" + snippet + "\n"
    js_path.write_text(code, encoding="utf-8")
    print("[OK] Đã thêm snippet ẩn Tool rules trên /datasource.")
else:
    print("[INFO] Snippet ẩn Tool rules đã tồn tại, không thêm nữa.")
PY

echo "[DONE] hide_tool_rules_on_datasource.sh hoàn thành."
