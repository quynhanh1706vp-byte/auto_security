#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/patch_sb_severity_chart.js"
CSS="$ROOT/static/css/security_resilient.css"

echo "[i] ROOT = $ROOT"
echo "[i] Ghi đè $JS (v3) + thêm CSS cho row mới..."

# 1) Ghi lại patch_sb_severity_chart.js
python3 - "$JS" <<'PY'
import sys, pathlib, textwrap

path = pathlib.Path(sys.argv[1])

code = textwrap.dedent("""
/**
 * patch_sb_severity_chart.js (v3)
 * - Tìm card 'SEVERITY BUCKETS'
 * - Đọc C=..., H=..., M=..., L=...
 * - Ẩn hàng cột cũ, vẽ hàng cột mới (4 div) theo %.
 */
document.addEventListener("DOMContentLoaded", function () {
  try {
    // 1) Tìm card SEVERITY BUCKETS
    var cards = Array.from(document.querySelectorAll(".sb-card, .card, .panel, .card-body, .sb-main"));
    var sevCard = cards.find(function (el) {
      return el.textContent && el.textContent.indexOf("SEVERITY BUCKETS") !== -1;
    });
    if (!sevCard) {
      console.warn("[SB][sev v3] Không tìm thấy card 'SEVERITY BUCKETS'");
      return;
    }

    // 2) Tìm legend C/H/M/L
    var legendNode = Array.from(sevCard.querySelectorAll("*")).find(function (el) {
      var t = (el.textContent || "").replace(/\\s+/g, " ").trim();
      return /C=\\d+/.test(t) && /H=\\d+/.test(t) && /M=\\d+/.test(t) && /L=\\d+/.test(t);
    });
    if (!legendNode) {
      console.warn("[SB][sev v3] Không tìm được legend C/H/M/L");
      return;
    }

    var text = legendNode.textContent.replace(/\\s+/g, " ");
    var m = text.match(/C=(\\d+).*H=(\\d+).*M=(\\d+).*L=(\\d+)/);
    if (!m) {
      console.warn("[SB][sev v3] Không parse được legend:", text);
      return;
    }

    var vals = [
      parseInt(m[1] || "0", 10),  // C
      parseInt(m[2] || "0", 10),  // H
      parseInt(m[3] || "0", 10),  // M
      parseInt(m[4] || "0", 10)   // L
    ];
    var total = vals.reduce(function (a, b) { return a + b; }, 0) || 1;
    console.log("[SB][sev v3] Legend =", vals, "total =", total);

    // 3) Ẩn hàng cột cũ (4 div thấp, có màu, nằm cùng 1 row flex)
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
      console.log("[SB][sev v3] Đã ẩn", smallColorDivs.length, "div nhỏ màu cũ");
    }

    // 4) Tạo row mới
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

      var barWrap = document.createElement("div");
      barWrap.className = "sb-bucket-wrap " + classes[idx];

      var bar = document.createElement("div");
      bar.className = "sb-bucket-bar " + classes[idx];
      bar.style.width = pct + "%";

      var label = document.createElement("div");
      label.className = "sb-bucket-label";
      label.textContent = labels[idx] + " (" + v + ")";

      barWrap.appendChild(bar);
      barWrap.appendChild(label);
      container.appendChild(barWrap);
    });

    // Chèn row mới ngay sau title (hoặc nếu không có, ở đầu card)
    if (titleNode && titleNode.parentNode === sevCard) {
      if (titleNode.nextSibling) {
        sevCard.insertBefore(container, titleNode.nextSibling);
      } else {
        sevCard.appendChild(container);
      }
    } else {
      sevCard.insertBefore(container, sevCard.firstChild);
    }

    console.log("[SB][sev v3] Đã render row severity mới.");
  } catch (e) {
    console.warn("[SB][sev v3] Lỗi khi patch severity chart:", e);
  }
});
""").lstrip()

path.write_text(code, encoding="utf-8")
print(f"[OK] Đã ghi {path}")
PY

# 2) Thêm CSS cho row mới (nếu chưa có)
python3 - "$CSS" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
css = path.read_text(encoding="utf-8")

marker = "/* [patch_sb_severity_chart_v3] */"
if marker in css:
  print("[i] CSS đã có patch_sb_severity_chart_v3 – bỏ qua.")
else:
  extra = """
/* [patch_sb_severity_chart_v3] Custom severity buckets row */
.sb-buckets-row-custom {
  margin-top: 12px;
  padding-top: 4px;
  border-top: 1px solid rgba(255,255,255,0.04);
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  grid-column-gap: 12px;
}

.sb-bucket-wrap {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.sb-bucket-bar {
  height: 6px;
  border-radius: 999px;
  opacity: 0.95;
}

/* màu tận dụng palette sẵn (đã gần giống trong UI gốc) */
.sb-bucket-bar.critical { background: linear-gradient(90deg, #ff4e50, #ff6a4d); }
.sb-bucket-bar.high     { background: linear-gradient(90deg, #ffb347, #ffcc33); }
.sb-bucket-bar.medium   { background: linear-gradient(90deg, #ffd866, #ffee99); }
.sb-bucket-bar.low      { background: linear-gradient(90deg, #84e184, #a8ffb0); }

.sb-bucket-label {
  font-size: 11px;
  opacity: 0.75;
}
"""
  css = css.rstrip() + "\\n" + extra + "\\n"
  path.write_text(css, encoding="utf-8")
  print("[OK] Đã append CSS patch_sb_severity_chart_v3")
PY

echo "[DONE] patch_sb_severity_chart_v3.sh hoàn thành."
