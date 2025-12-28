#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/sb_severity_patch_v1.js"
CSS="$ROOT/static/css/security_resilient.css"
INDEX="$ROOT/templates/index.html"

echo "[i] ROOT = $ROOT"

# 1) Tạo file JS: đọc dòng 'C=..., H=..., M=..., L=...' và scale width 4 cột
python3 - "$JS" <<'PY'
import sys, pathlib, textwrap

path = pathlib.Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)

code = textwrap.dedent("""
/**
 * sb_severity_patch_v1.js
 * Dùng text 'C=..., H=..., M=..., L=...' trong card SEVERITY BUCKETS
 * để set width % cho 4 thanh cột.
 */
document.addEventListener("DOMContentLoaded", function () {
  try {
    var cards = Array.from(document.querySelectorAll(".sb-card, .card, .panel"));
    var sevCard = cards.find(function (el) {
      return el.textContent && el.textContent.indexOf("SEVERITY BUCKETS") !== -1;
    });
    if (!sevCard) return;

    // Tìm element chứa text C=..., H=..., M=..., L=...
    var legend = Array.from(sevCard.querySelectorAll("*")).find(function (el) {
      var t = (el.textContent || "").trim();
      return t.indexOf("C=") !== -1 && t.indexOf("H=") !== -1 &&
             t.indexOf("M=") !== -1 && t.indexOf("L=") !== -1;
    });
    if (!legend) return;

    var text = legend.textContent.replace(/\\s+/g, " ");
    var m = text.match(/C=(\\d+).*H=(\\d+).*M=(\\d+).*L=(\\d+)/);
    if (!m) return;

    var vals = [
      parseInt(m[1] || "0", 10),
      parseInt(m[2] || "0", 10),
      parseInt(m[3] || "0", 10),
      parseInt(m[4] || "0", 10)
    ];
    var total = vals.reduce(function (a, b) { return a + b; }, 0) || 1;

    // Lấy 4 thanh trong card
    var bars = sevCard.querySelectorAll(".sb-sev-bar, .sb-severity-bar, .severity-bar");
    if (!bars.length) return;

    Array.from(bars).slice(0, 4).forEach(function (el, idx) {
      var v = vals[idx] || 0;
      var pct = Math.round(v / total * 100);
      // Nếu có value mà % quá nhỏ thì cho tối thiểu 3% để vẫn nhìn thấy
      if (v > 0 && pct < 3) pct = 3;
      if (pct < 0) pct = 0;
      if (pct > 100) pct = 100;
      el.style.width = pct + "%";
    });
  } catch (e) {
    if (window.console && console.warn) {
      console.warn("[SB] severity patch error:", e);
    }
  }
});
""").lstrip()

path.write_text(code, encoding="utf-8")
print(f"[OK] Đã ghi {path}")
PY

# 2) Gắn script này vào templates/index.html
python3 - "$INDEX" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")
tag = "sb_severity_patch_v1.js"

if tag in data:
    print("[i] templates/index.html đã có sb_severity_patch_v1.js – bỏ qua.")
else:
    # Ưu tiên chèn sau dòng index_fallback_dashboard.js nếu có
    marker = "index_fallback_dashboard.js"
    idx = data.find(marker)
    if idx != -1:
        insert_pos = data.find("\\n", idx)
        if insert_pos == -1:
            insert_pos = idx + len(marker)
    else:
        # fallback: chèn trước </body>
        lower = data.lower()
        marker = "</body>"
        idx = lower.rfind(marker)
        if idx == -1:
            raise SystemExit("[ERR] Không tìm được vị trí để chèn script trong index.html")
        insert_pos = idx

    snippet = '  <script src="{{ url_for(\\'static\\', filename=\\'sb_severity_patch_v1.js\\') }}"></script>\\n'
    data = data[:insert_pos] + "\\n" + snippet + data[insert_pos:]
    path.write_text(data, encoding="utf-8")
    print("[OK] Đã chèn script sb_severity_patch_v1.js vào templates/index.html")
PY

# 3) Thêm CSS override để các thanh cột dùng width, không ép flex:1
python3 - "$CSS" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
css = path.read_text(encoding="utf-8")

marker = "/* [patch_severity_bucket_v1] */"
if marker in css:
    print("[i] security_resilient.css đã có patch_severity_bucket_v1 – bỏ qua.")
else:
    extra = """
/* [patch_severity_bucket_v1] Fix severity buckets bar width */
.sb-sev-row,
.sb-severity-bars {
  display: flex;
}
.sb-sev-bar {
  flex: 0 0 auto !important;  /* để width % điều khiển chiều dài */
}
"""
    css = css.rstrip() + "\\n" + extra + "\\n"
    path.write_text(css, encoding="utf-8")
    print("[OK] Đã append patch_severity_bucket_v1 vào security_resilient.css")
PY

echo "[DONE] patch_severity_bucket_fix_v1.sh hoàn thành."
