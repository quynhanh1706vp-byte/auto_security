#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/patch_sb_severity_chart.js"

echo "[i] ROOT = $ROOT"
echo "[i] Ghi đè $JS – chỉ ẩn các block dư, giữ legend trên."

python3 - "$JS" <<'PY'
import sys, pathlib, textwrap

path = pathlib.Path(sys.argv[1])

code = textwrap.dedent("""
/**
 * patch_sb_severity_chart.js (reset_clean)
 *
 * Mục tiêu:
 * - Giữ nguyên legend đẹp ở phía trên (4 ô màu + số).
 * - Ẩn mọi block dư phía dưới (chart cũ, chart mới, dòng lặp Critical/High/Medium/Low).
 * - Không vẽ thêm gì mới, tránh làm vỡ layout.
 */
document.addEventListener("DOMContentLoaded", function () {
  try {
    // 1) Tìm card SEVERITY BUCKETS
    var cards = Array.from(document.querySelectorAll(".sb-card, .card, .panel, .card-body, .sb-main"));
    var sevCard = cards.find(function (el) {
      return el.textContent && el.textContent.indexOf("SEVERITY BUCKETS") !== -1;
    });
    if (!sevCard) {
      console.warn("[SB][sev reset] Không tìm thấy card 'SEVERITY BUCKETS'");
      return;
    }

    // 2) Ẩn mọi chart custom mình đã tạo (nếu còn)
    Array.from(sevCard.querySelectorAll(".sb-buckets-chart-new, .sb-buckets-row-custom"))
      .forEach(function (el) { el.remove(); });

    // 3) Trong card, có thể có nhiều block chứa các chữ Critical/High/Medium/Low.
    //    Ta giữ lại block đầu tiên, ẩn TẤT CẢ các block còn lại có đủ 4 chữ này.
    var allBlocks = Array.from(sevCard.querySelectorAll("div"));
    var foundFirstLegend = false;

    allBlocks.forEach(function (el) {
      var t = (el.textContent || "").replace(/\\s+/g, " ").trim();
      if (!t) return;

      var hasAll =
        t.indexOf("Critical") !== -1 &&
        t.indexOf("High")     !== -1 &&
        t.indexOf("Medium")   !== -1 &&
        t.indexOf("Low")      !== -1;

      if (!hasAll) return;

      if (!foundFirstLegend) {
        // Đây là block legend đầu tiên -> giữ lại
        foundFirstLegend = true;
      } else {
        // Các block legend sau (dưới cùng) -> ẩn đi
        el.style.display = "none";
      }
    });

    console.log("[SB][sev reset] Đã giữ legend đầu tiên, ẩn các block dư.");
  } catch (e) {
    console.warn("[SB][sev reset] Lỗi khi dọn severity chart:", e);
  }
});
""").lstrip()

path.write_text(code, encoding="utf-8")
print(f"[OK] Đã ghi {path}")
PY

echo "[DONE] patch_sb_severity_chart_reset_clean.sh hoàn thành."
