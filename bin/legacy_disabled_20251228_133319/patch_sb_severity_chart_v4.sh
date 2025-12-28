#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/patch_sb_severity_chart.js"

echo "[i] ROOT = $ROOT"
echo "[i] Ghi đè $JS (v4) – giữ hàng mới, ẩn biểu đồ cũ bên dưới..."

python3 - "$JS" <<'PY'
import sys, pathlib, textwrap

path = pathlib.Path(sys.argv[1])

code = textwrap.dedent("""
/**
 * patch_sb_severity_chart.js (v4)
 * - Tìm card 'SEVERITY BUCKETS'
 * - Đọc C=..., H=..., M=..., L=...
 * - Ẩn dãy cột màu cũ (nếu có)
 * - Vẽ lại hàng cột mới theo % (Critical/High/Medium/Low)
 * - Ẩn luôn phần legend/bars cũ ở cuối card (nếu còn).
 */
document.addEventListener("DOMContentLoaded", function () {
  try {
    // 1) Tìm card SEVERITY BUCKETS
    var cards = Array.from(document.querySelectorAll(".sb-card, .card, .panel, .card-body, .sb-main"));
    var sevCard = cards.find(function (el) {
      return el.textContent && el.textContent.indexOf("SEVERITY BUCKETS") !== -1;
    });
    if (!sevCard) {
      console.warn("[SB][sev v4] Không tìm thấy card 'SEVERITY BUCKETS'");
      return;
    }

    // 2) Tìm legend C/H/M/L
    var legendNode = Array.from(sevCard.querySelectorAll("*")).find(function (el) {
      var t = (el.textContent || "").replace(/\\s+/g, " ").trim();
      return /C=\\d+/.test(t) && /H=\\d+/.test(t) && /M=\\d+/.test(t) && /L=\\d+/.test(t);
    });
    if (!legendNode) {
      console.warn("[SB][sev v4] Không tìm được legend C/H/M/L");
      return;
    }

    var text = legendNode.textContent.replace(/\\s+/g, " ");
    var m = text.match(/C=(\\d+).*H=(\\d+).*M=(\\d+).*L=(\\d+)/);
    if (!m) {
      console.warn("[SB][sev v4] Không parse được legend:", text);
      return;
    }

    var vals = [
      parseInt(m[1] || "0", 10),  // C
      parseInt(m[2] || "0", 10),  // H
      parseInt(m[3] || "0", 10),  // M
      parseInt(m[4] || "0", 10)   // L
    ];
    var total = vals.reduce(function (a, b) { return a + b; }, 0) || 1;
    console.log("[SB][sev v4] Legend =", vals, "total =", total);

    // 3) Ẩn các div cột màu cũ (nếu tìm được)
    var allDivs = Array.from(sevCard.querySelectorAll("div"));
    var smallColorDivs = allDivs.filter(function (el) {
      var style = window.getComputedStyle(el);
      var h = parseFloat(style.height) || 0;
      var bg = style.backgroundColor || "";
      if (!(h > 0 && h <= 12)) return false;
      if (!bg || bg === "rgba(0, 0, 0, 0)" || bg === "transparent") return false;
      return true;
    });
    if (smallColorDivs.length) {
      smallColorDivs.forEach(function (el) {
        el.style.display = "none";
      });
      console.log("[SB][sev v4] Đã ẩn", smallColorDivs.length, "div cột màu cũ");
    }

    // 4) Render hàng severity mới (nếu chưa có)
    if (!sevCard.querySelector(".sb-buckets-row-custom")) {
      var titleNode = Array.from(sevCard.querySelectorAll("*")).find(function (el) {
        var t = (el.textContent || "").replace(/\\s+/g, " ").trim();
        return t === "SEVERITY BUCKETS";
      }) || sevCard.firstElementChild;

      var container = document.createElement("div");
      container.className = "sb-buckets-row-custom";

      var labels = ["Critical", "High", "Medium", "Low"];
      var classes = ["critical", "high", "medium", "low"];

      vals.forEach(function (v, idx) {
        var pct = Math.round(v / total * 100);
        if (v > 0 && pct < 3) pct = 3;
        if (pct < 0) pct = 0;
        if (pct > 100) pct = 100;

        var wrap = document.createElement("div");
        wrap.className = "sb-bucket-wrap " + classes[idx];

        var bar = document.createElement("div");
        bar.className = "sb-bucket-bar " + classes[idx];
        bar.style.width = pct + "%";

        var label = document.createElement("div");
        label.className = "sb-bucket-label";
        label.textContent = labels[idx] + " (" + v + ")";

        wrap.appendChild(bar);
        wrap.appendChild(label);
        container.appendChild(wrap);
      });

      if (titleNode && titleNode.parentNode === sevCard) {
        if (titleNode.nextSibling) {
          sevCard.insertBefore(container, titleNode.nextSibling);
        } else {
          sevCard.appendChild(container);
        }
      } else {
        sevCard.insertBefore(container, sevCard.firstChild);
      }

      console.log("[SB][sev v4] Đã render row severity mới.");
    }

    // 5) Ẩn legend/bars cũ ở cuối card (nếu còn)
    try {
      var children = Array.from(sevCard.children).reverse();  // bắt đầu từ cuối
      for (var i = 0; i < children.length; i++) {
        var el = children[i];
        var t = (el.textContent || "").replace(/\\s+/g, " ").trim();
        if (!t) continue;
        if (t.indexOf("Critical") !== -1 &&
            t.indexOf("High") !== -1 &&
            t.indexOf("Medium") !== -1 &&
            t.indexOf("Low") !== -1) {
          el.style.display = "none";
          console.log("[SB][sev v4] Đã ẩn block legend/bars cũ ở cuối card.");
          break;
        }
      }
    } catch (e2) {
      console.warn("[SB][sev v4] Lỗi khi ẩn legend cũ:", e2);
    }

  } catch (e) {
    console.warn("[SB][sev v4] Lỗi khi patch severity chart:", e);
  }
});
""").lstrip()

path.write_text(code, encoding="utf-8")
print(f"[OK] Đã ghi {path}")
PY

echo "[DONE] patch_sb_severity_chart_v4.sh hoàn thành."
