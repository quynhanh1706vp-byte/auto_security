#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/patch_sb_severity_chart.js"

echo "[i] ROOT = $ROOT"
echo "[i] Ghi đè $JS (v6)..."

python3 - "$JS" <<'PY'
import sys, pathlib, textwrap

path = pathlib.Path(sys.argv[1])

code = textwrap.dedent("""
/**
 * patch_sb_severity_chart.js (v6)
 * - Tìm card 'SEVERITY BUCKETS'
 * - Đọc C=..., H=..., M=..., L=...
 * - Ẩn bar cũ + block legend cũ bên dưới
 * - Vẽ lại 1 hàng grid mới: Critical / High / Medium / Low với bar dài/ngắn theo %.
 */
document.addEventListener("DOMContentLoaded", function () {
  try {
    // 1) Tìm card SEVERITY BUCKETS
    var cards = Array.from(document.querySelectorAll(".sb-card, .card, .panel, .card-body, .sb-main"));
    var sevCard = cards.find(function (el) {
      return el.textContent && el.textContent.indexOf("SEVERITY BUCKETS") !== -1;
    });
    if (!sevCard) {
      console.warn("[SB][sev v6] Không tìm thấy card 'SEVERITY BUCKETS'");
      return;
    }

    // Xoá grid custom cũ (nếu có)
    Array.from(sevCard.querySelectorAll(".sb-buckets-row-custom")).forEach(function (el) { el.remove(); });

    // 2) Tìm legend C/H/M/L
    var legendNode = Array.from(sevCard.querySelectorAll("*")).find(function (el) {
      var t = (el.textContent || "").replace(/\\s+/g, " ").trim();
      return /C=\\d+/.test(t) && /H=\\d+/.test(t) && /M=\\d+/.test(t) && /L=\\d+/.test(t);
    });
    if (!legendNode) {
      console.warn("[SB][sev v6] Không tìm được legend C/H/M/L");
      return;
    }

    var text = legendNode.textContent.replace(/\\s+/g, " ");
    var m = text.match(/C=(\\d+).*H=(\\d+).*M=(\\d+).*L=(\\d+)/);
    if (!m) {
      console.warn("[SB][sev v6] Không parse được legend:", text);
      return;
    }

    var C = parseInt(m[1] || "0", 10);
    var H = parseInt(m[2] || "0", 10);
    var M = parseInt(m[3] || "0", 10);
    var L = parseInt(m[4] || "0", 10);
    var total = C + H + M + L || 1;
    console.log("[SB][sev v6] C/H/M/L =", C, H, M, L, "total =", total);

    function pct(v) {
      var p = Math.round(v / total * 100);
      if (v > 0 && p < 3) p = 3;
      if (p < 0) p = 0;
      if (p > 100) p = 100;
      return p;
    }

    // 3) Ẩn mọi bar màu cũ (cả block legend dưới)
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
      console.log("[SB][sev v6] Đã ẩn", smallColorDivs.length, "div bar màu cũ");
    }

    // Block legend dưới cùng: chứa cả chữ Critical/High/Medium/Low + số
    var legendBlocks = allDivs.filter(function (el) {
      var t = (el.textContent || "").replace(/\\s+/g, " ").trim();
      return t.indexOf("Critical") !== -1 &&
             t.indexOf("High")     !== -1 &&
             t.indexOf("Medium")   !== -1 &&
             t.indexOf("Low")      !== -1;
    });
    legendBlocks.forEach(function (el) { el.style.display = "none"; });

    // 4) Tạo hàng grid mới
    var titleNode = Array.from(sevCard.querySelectorAll("*")).find(function (el) {
      var t = (el.textContent || "").replace(/\\s+/g, " ").trim();
      return t === "SEVERITY BUCKETS";
    }) || sevCard.firstElementChild;

    var container = document.createElement("div");
    container.className = "sb-buckets-row-custom";

    var defs = [
      { key: "critical", label: "Critical", value: C },
      { key: "high",     label: "High",     value: H },
      { key: "medium",   label: "Medium",   value: M },
      { key: "low",      label: "Low",      value: L },
    ];

    defs.forEach(function (cfg) {
      var wrap = document.createElement("div");
      wrap.className = "sb-bucket-wrap " + cfg.key;

      var label = document.createElement("div");
      label.className = "sb-bucket-label";
      label.textContent = cfg.label + " (" + cfg.value + ")";

      var bar = document.createElement("div");
      bar.className = "sb-bucket-bar-custom sb-" + cfg.key;
      bar.style.width = pct(cfg.value) + "%";

      wrap.appendChild(label);
      wrap.appendChild(bar);
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

    console.log("[SB][sev v6] Đã render grid severity mới.");
  } catch (e) {
    console.warn("[SB][sev v6] Lỗi khi patch severity chart:", e);
  }
});
""").lstrip()

path.write_text(code, encoding="utf-8")
print(f"[OK] Đã ghi {path}")
PY

echo "[DONE] patch_sb_severity_chart_v6.sh hoàn thành."
