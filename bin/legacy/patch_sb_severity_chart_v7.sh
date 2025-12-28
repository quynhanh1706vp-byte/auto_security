#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/patch_sb_severity_chart.js"
CSS="$ROOT/static/css/security_resilient.css"

echo "[i] ROOT = $ROOT"
echo "[i] Ghi đè $JS (v7) – biểu đồ cột đứng 4 mức severity..."

# 1) Ghi lại patch_sb_severity_chart.js (mới hoàn toàn)
python3 - "$JS" <<'PY'
import sys, pathlib, textwrap

path = pathlib.Path(sys.argv[1])

code = textwrap.dedent("""
/**
 * patch_sb_severity_chart.js (v7)
 * - Tìm card 'SEVERITY BUCKETS'
 * - Đọc C=..., H=..., M=..., L=...
 * - Vẽ biểu đồ cột đứng 4 cột (Critical/High/Medium/Low) ở cuối card.
 */
document.addEventListener("DOMContentLoaded", function () {
  try {
    // 1) Tìm card SEVERITY BUCKETS
    var cards = Array.from(document.querySelectorAll(".sb-card, .card, .panel, .card-body, .sb-main"));
    var sevCard = cards.find(function (el) {
      return el.textContent && el.textContent.indexOf("SEVERITY BUCKETS") !== -1;
    });
    if (!sevCard) {
      console.warn("[SB][sev v7] Không tìm thấy card 'SEVERITY BUCKETS'");
      return;
    }

    // Xoá biểu đồ cũ của chính script này nếu tồn tại
    var oldChart = sevCard.querySelector(".sb-buckets-chart-new");
    if (oldChart) oldChart.remove();

    // 2) Tìm dòng legend C/H/M/L
    var legendNode = Array.from(sevCard.querySelectorAll("*")).find(function (el) {
      var t = (el.textContent || "").replace(/\\s+/g, " ").trim();
      return /C=\\d+/.test(t) && /H=\\d+/.test(t) && /M=\\d+/.test(t) && /L=\\d+/.test(t);
    });
    if (!legendNode) {
      console.warn("[SB][sev v7] Không tìm được legend C/H/M/L");
      return;
    }

    var text = legendNode.textContent.replace(/\\s+/g, " ");
    var m = text.match(/C=(\\d+).*H=(\\d+).*M=(\\d+).*L=(\\d+)/);
    if (!m) {
      console.warn("[SB][sev v7] Không parse được legend:", text);
      return;
    }

    var C = parseInt(m[1] || "0", 10);
    var H = parseInt(m[2] || "0", 10);
    var M = parseInt(m[3] || "0", 10);
    var L = parseInt(m[4] || "0", 10);
    var max = Math.max(C, H, M, L, 1);
    console.log("[SB][sev v7] C/H/M/L =", C, H, M, L, "max =", max);

    function hPct(v) {
      var p = Math.round(v / max * 100);
      if (v > 0 && p < 10) p = 10;   // có số mà quá thấp thì vẫn cho tối thiểu 10% để nhìn thấy
      if (p < 0) p = 0;
      if (p > 100) p = 100;
      return p;
    }

    var defs = [
      { key: "critical", label: "Critical", value: C },
      { key: "high",     label: "High",     value: H },
      { key: "medium",   label: "Medium",   value: M },
      { key: "low",      label: "Low",      value: L },
    ];

    // 3) Tạo container biểu đồ
    var chart = document.createElement("div");
    chart.className = "sb-buckets-chart-new";

    var bars = document.createElement("div");
    bars.className = "sb-buckets-bars-new";

    defs.forEach(function (cfg) {
      var col = document.createElement("div");
      col.className = "sb-bucket-col-new sb-" + cfg.key;

      var bar = document.createElement("div");
      bar.className = "sb-bucket-bar-new sb-" + cfg.key;
      bar.style.height = hPct(cfg.value) + "%";

      var label = document.createElement("div");
      label.className = "sb-bucket-col-label";
      label.textContent = cfg.label;

      var val = document.createElement("div");
      val.className = "sb-bucket-col-value";
      val.textContent = cfg.value;

      col.appendChild(bar);
      col.appendChild(label);
      col.appendChild(val);
      bars.appendChild(col);
    });

    chart.appendChild(bars);

    // 4) Chèn chart sau dòng legend C/H/M/L (hoặc cuối card nếu không được)
    var insertAfter = legendNode;
    if (insertAfter && insertAfter.parentNode === sevCard) {
      if (insertAfter.nextSibling) {
        sevCard.insertBefore(chart, insertAfter.nextSibling);
      } else {
        sevCard.appendChild(chart);
      }
    } else {
      sevCard.appendChild(chart);
    }

    console.log("[SB][sev v7] Đã render biểu đồ cột đứng mới.");
  } catch (e) {
    console.warn("[SB][sev v7] Lỗi khi patch severity chart:", e);
  }
});
""").lstrip()

path.write_text(code, encoding="utf-8")
print(f"[OK] Đã ghi {path}")
PY

# 2) CSS cho biểu đồ cột đứng
python3 - "$CSS" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
css = path.read_text(encoding="utf-8")

marker = "/* [sb_severity_chart_new_v1] */"
if marker in css:
  print("[i] CSS đã có sb_severity_chart_new_v1 – bỏ qua.")
else:
  extra = """
/* [sb_severity_chart_new_v1] Biểu đồ cột đứng SEVERITY BUCKETS */
.sb-buckets-chart-new {
  margin-top: 12px;
  padding-top: 8px;
  border-top: 1px solid rgba(255,255,255,0.06);
}

.sb-buckets-bars-new {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 16px;
  height: 120px;  /* chiều cao vùng cột */
}

.sb-bucket-col-new {
  flex: 1;
  text-align: center;
  font-size: 11px;
}

.sb-bucket-bar-new {
  width: 55%;
  margin: 0 auto 4px;
  border-radius: 4px;
  opacity: 0.95;
}

/* Màu theo severity, gần giống palette gốc */
.sb-bucket-bar-new.sb-critical {
  background: linear-gradient(180deg, #ff4e50, #ff6a4d);
}
.sb-bucket-bar-new.sb-high {
  background: linear-gradient(180deg, #ffb347, #ffcc33);
}
.sb-bucket-bar-new.sb-medium {
  background: linear-gradient(180deg, #ffd866, #ffee99);
}
.sb-bucket-bar-new.sb-low {
  background: linear-gradient(180deg, #84e184, #a8ffb0);
}

.sb-bucket-col-label {
  margin-top: 0;
  opacity: 0.8;
}

.sb-bucket-col-value {
  opacity: 0.8;
}
"""
  css = css.rstrip() + "\\n" + extra + "\\n"
  path.write_text(css, encoding="utf-8")
  print("[OK] Đã append CSS sb_severity_chart_new_v1")
PY

echo "[DONE] patch_sb_severity_chart_v7.sh hoàn thành."
