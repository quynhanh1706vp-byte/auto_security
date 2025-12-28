#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/patch_sb_severity_chart.js"
CSS="$ROOT/static/css/security_resilient.css"

echo "[i] ROOT = $ROOT"
echo "[i] Ghi đè $JS (v5) – 4 thanh dọc chuẩn màu, chuẩn %..."

python3 - "$JS" <<'PY'
import sys, pathlib, textwrap

path = pathlib.Path(sys.argv[1])

code = textwrap.dedent("""
/**
 * patch_sb_severity_chart.js (v5)
 * - Dùng legend C=..., H=..., M=..., L=...
 * - Ẩn các bar cũ (cả hàng legend màu dưới nếu còn).
 * - Với từng dòng Critical/High/Medium/Low chèn 1 bar mới ngay dưới label:
 *   + width = % tương ứng
 *   + màu theo severity.
 */
document.addEventListener("DOMContentLoaded", function () {
  try {
    // 1) Tìm card SEVERITY BUCKETS
    var cards = Array.from(document.querySelectorAll(".sb-card, .card, .panel, .card-body, .sb-main"));
    var sevCard = cards.find(function (el) {
      return el.textContent && el.textContent.indexOf("SEVERITY BUCKETS") !== -1;
    });
    if (!sevCard) {
      console.warn("[SB][sev v5] Không tìm thấy card 'SEVERITY BUCKETS'");
      return;
    }

    // Xoá hàng grid custom cũ (nếu còn)
    Array.from(sevCard.querySelectorAll(".sb-buckets-row-custom")).forEach(function (el) { el.remove(); });

    // 2) Tìm legend C/H/M/L
    var legendNode = Array.from(sevCard.querySelectorAll("*")).find(function (el) {
      var t = (el.textContent || "").replace(/\\s+/g, " ").trim();
      return /C=\\d+/.test(t) && /H=\\d+/.test(t) && /M=\\d+/.test(t) && /L=\\d+/.test(t);
    });
    if (!legendNode) {
      console.warn("[SB][sev v5] Không tìm được legend C/H/M/L");
      return;
    }

    var text = legendNode.textContent.replace(/\\s+/g, " ");
    var m = text.match(/C=(\\d+).*H=(\\d+).*M=(\\d+).*L=(\\d+)/);
    if (!m) {
      console.warn("[SB][sev v5] Không parse được legend:", text);
      return;
    }

    var C = parseInt(m[1] || "0", 10);
    var H = parseInt(m[2] || "0", 10);
    var M = parseInt(m[3] || "0", 10);
    var L = parseInt(m[4] || "0", 10);
    var total = C + H + M + L || 1;
    console.log("[SB][sev v5] C/H/M/L =", C, H, M, L, "total =", total);

    // 3) Ẩn mọi bar màu cũ (cả hàng legend bên dưới)
    var allDivs = Array.from(sevCard.querySelectorAll("div"));
    var smallColorDivs = allDivs.filter(function (el) {
      var style = window.getComputedStyle(el);
      var h = parseFloat(style.height) || 0;
      var bg = style.backgroundColor || "";
      if (!(h > 0 && h <= 12)) return false;
      if (!bg || bg === "rgba(0, 0, 0, 0)" || bg === "transparent") return false;
      return true;
    });
    smallColorDivs.forEach(function (el) { el.style.display = "none"; });
    if (smallColorDivs.length) {
      console.log("[SB][sev v5] Đã ẩn", smallColorDivs.length, "div bar màu cũ");
    }

    // 4) Helper: tạo bar mới dưới label
    function makeBar(widthPct, severity) {
      var bar = document.createElement("div");
      bar.className = "sb-bucket-bar-custom sb-" + severity;
      bar.style.width = widthPct + "%";
      return bar;
    }

    function pct(v) {
      var p = Math.round(v / total * 100);
      if (v > 0 && p < 3) p = 3;   // có dữ liệu mà quá nhỏ thì vẫn cho 3%
      if (p < 0) p = 0;
      if (p > 100) p = 100;
      return p;
    }

    // 5) Với mỗi severity: tìm label dòng 'Critical (..)' rồi chèn bar
    var defs = [
      { key: "critical", label: "Critical", value: C },
      { key: "high",     label: "High",     value: H },
      { key: "medium",   label: "Medium",   value: M },
      { key: "low",      label: "Low",      value: L },
    ];

    defs.forEach(function (cfg) {
      var labelNode = Array.from(sevCard.querySelectorAll("*")).find(function (el) {
        var t = (el.textContent || "").replace(/\\s+/g, " ").trim();
        return t.indexOf(cfg.label + " (") === 0;   // ví dụ: "High (170)"
      });
      if (!labelNode) {
        console.warn("[SB][sev v5] Không tìm thấy label dòng", cfg.label);
        return;
      }

      // Xoá các bar custom cũ ngay sau label (nếu có)
      var sib = labelNode.nextSibling;
      while (sib && sib.nodeType === 1 && sib.classList.contains("sb-bucket-bar-custom")) {
        var toRemove = sib;
        sib = sib.nextSibling;
        toRemove.remove();
      }

      var p = pct(cfg.value);
      var bar = makeBar(p, cfg.key);

      // Chèn ngay sau label
      if (labelNode.parentNode) {
        labelNode.parentNode.insertBefore(bar, labelNode.nextSibling);
      }
    });

    console.log("[SB][sev v5] Đã render 4 thanh dọc custom cho SEVERITY BUCKETS.");
  } catch (e) {
    console.warn("[SB][sev v5] Lỗi khi patch severity chart:", e);
  }
});
""").lstrip()

path.write_text(code, encoding="utf-8")
print(f"[OK] Đã ghi {path}")
PY

# 2) CSS cho bar custom (màu + chiều cao)
python3 - "$CSS" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
css = path.read_text(encoding="utf-8")

marker = "/* [patch_sb_severity_chart_v5] */"
if marker in css:
  print("[i] CSS đã có patch_sb_severity_chart_v5 – bỏ qua.")
else:
  extra = """
/* [patch_sb_severity_chart_v5] Bar dọc SEVERITY BUCKETS */
.sb-bucket-bar-custom {
  height: 6px;
  border-radius: 999px;
  margin-top: 4px;
  margin-bottom: 6px;
  opacity: 0.95;
}

/* màu theo severity – bám gần palette gốc */
.sb-bucket-bar-custom.sb-critical {
  background: linear-gradient(90deg, #ff4e50, #ff6a4d);
}
.sb-bucket-bar-custom.sb-high {
  background: linear-gradient(90deg, #ffb347, #ffcc33);
}
.sb-bucket-bar-custom.sb-medium {
  background: linear-gradient(90deg, #ffd866, #ffee99);
}
.sb-bucket-bar-custom.sb-low {
  background: linear-gradient(90deg, #84e184, #a8ffb0);
}
"""
  css = css.rstrip() + "\\n" + extra + "\\n"
  path.write_text(css, encoding="utf-8")
  print("[OK] Đã append CSS patch_sb_severity_chart_v5")
PY

echo "[DONE] patch_sb_severity_chart_v5.sh hoàn thành."
