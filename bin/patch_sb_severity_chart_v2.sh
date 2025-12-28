#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/patch_sb_severity_chart.js"

echo "[i] ROOT = $ROOT"
echo "[i] Ghi đè $JS với logic scale cột theo C/H/M/L..."

python3 - "$JS" <<'PY'
import sys, pathlib, textwrap

path = pathlib.Path(sys.argv[1])
code = textwrap.dedent("""
/**
 * patch_sb_severity_chart.js (v2)
 * - Tìm card "SEVERITY BUCKETS"
 * - Đọc text C=..., H=..., M=..., L=...
 * - Scale lại 4 cột theo % tương ứng
 */
document.addEventListener("DOMContentLoaded", function () {
  try {
    // 1) Tìm card SEVERITY BUCKETS
    var cards = Array.from(document.querySelectorAll(".sb-card, .card, .panel, .card-body, .sb-main"));
    var sevCard = cards.find(function (el) {
      return el.textContent && el.textContent.indexOf("SEVERITY BUCKETS") !== -1;
    });
    if (!sevCard) {
      console.warn("[SB][sev] Không tìm thấy card 'SEVERITY BUCKETS'");
      return;
    }

    // 2) Tìm text "C=..., H=..., M=..., L=..."
    var legendNode = Array.from(sevCard.querySelectorAll("*")).find(function (el) {
      var t = (el.textContent || "").replace(/\\s+/g, " ").trim();
      return /C=\\d+/.test(t) && /H=\\d+/.test(t) && /M=\\d+/.test(t) && /L=\\d+/.test(t);
    });
    if (!legendNode) {
      console.warn("[SB][sev] Không tìm được legend C/H/M/L trong card");
      return;
    }

    var text = legendNode.textContent.replace(/\\s+/g, " ");
    var m = text.match(/C=(\\d+).*H=(\\d+).*M=(\\d+).*L=(\\d+)/);
    if (!m) {
      console.warn("[SB][sev] Không parse được legend:", text);
      return;
    }

    var vals = [
      parseInt(m[1] || "0", 10),  // C
      parseInt(m[2] || "0", 10),  // H
      parseInt(m[3] || "0", 10),  // M
      parseInt(m[4] || "0", 10)   // L
    ];
    var total = vals.reduce(function (a, b) { return a + b; }, 0) || 1;

    // 3) Tìm 4 thanh màu trong card
    //    Heuristic: div có background != transparent, height nhỏ (<= 10px)
    var candidates = Array.from(sevCard.querySelectorAll("div")).filter(function (el) {
      var style = window.getComputedStyle(el);
      var h = parseFloat(style.height) || 0;
      var bg = style.backgroundColor || "";
      if (!(h > 0 && h <= 12)) return false;
      if (!bg || bg === "rgba(0, 0, 0, 0)" || bg === "transparent") return false;
      return true;
    });

    if (!candidates.length) {
      console.warn("[SB][sev] Không tìm thấy div nào có vẻ là cột severity");
      return;
    }

    // Sắp xếp theo vị trí X để có thứ tự Critical, High, Medium, Low
    candidates.sort(function (a, b) {
      return a.getBoundingClientRect().left - b.getBoundingClientRect().left;
    });

    var bars = candidates.slice(0, 4);
    if (bars.length < 4) {
      console.warn("[SB][sev] Ít hơn 4 thanh cột, tìm được:", bars.length);
    }

    bars.forEach(function (el, idx) {
      var v = vals[idx] || 0;
      var pct = Math.round(v / total * 100);
      if (v > 0 && pct < 3) pct = 3;  // có dữ liệu nhưng quá nhỏ thì vẫn cho tối thiểu 3%
      if (pct < 0) pct = 0;
      if (pct > 100) pct = 100;

      // Inline style để override hầu hết CSS khác
      el.style.flex = "0 0 " + pct + "%";
      el.style.width = pct + "%";
      el.style.maxWidth = pct + "%";
    });

    console.log("[SB][sev] Đã scale lại cột severity theo C/H/M/L:", vals);
  } catch (e) {
    console.warn("[SB][sev] Lỗi khi patch severity chart:", e);
  }
});
""").lstrip()

path.write_text(code, encoding="utf-8")
print(f"[OK] Đã ghi {path}")
PY

echo "[DONE] patch_sb_severity_chart_v2.sh hoàn thành."
