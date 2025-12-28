#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/patch_sb_severity_chart.js"

echo "[i] ROOT = $ROOT"
echo "[i] Ghi đè $JS – dùng RUN OVERVIEW vẽ 4 cột đứng trong card SEVERITY BUCKETS."

python3 - "$JS" <<'PY'
from pathlib import Path
import textwrap

path = Path("static/patch_sb_severity_chart.js")

code = textwrap.dedent(r"""
/**
 * patch_sb_severity_chart.js – FINAL SAFE COLUMN
 * - Lấy C/H/M/L từ RUN OVERVIEW (Totals: ... (C=..., H=..., M=..., L=...)).
 * - Tìm card SEVERITY BUCKETS (ancestor có class sb-card/card).
 * - Ẩn legend text bên trong card (Critical/High/Medium/Low).
 * - Vẽ 4 cột đứng Critical / High / Medium / Low ở cuối card.
 * - Không đụng tới app.py, không xóa card bên ngoài.
 */
document.addEventListener("DOMContentLoaded", function () {
  try {
    // 1) Lấy số C/H/M/L từ RUN OVERVIEW
    function getCounts() {
      let C = 0, H = 0, M = 0, L = 0;

      const totalsNode = Array.from(document.querySelectorAll("div, span, p")).find(el => {
        const t = el.textContent || "";
        return t.includes("Totals:") && t.includes("C=") && t.includes("H=") && t.includes("M=") && t.includes("L=");
      });

      if (!totalsNode) {
        console.warn("[SB][sev] Không tìm thấy dòng Totals(C/H/M/L) trong RUN OVERVIEW");
        return { C, H, M, L };
      }

      const txt = (totalsNode.textContent || "").replace(/\s+/g, " ");
      const m = txt.match(/C\s*=\s*(\d+)[^0-9]+H\s*=\s*(\d+)[^0-9]+M\s*=\s*(\d+)[^0-9]+L\s*=\s*(\d+)/i);
      if (!m) {
        console.warn("[SB][sev] Không parse được C/H/M/L từ:", txt);
        return { C, H, M, L };
      }

      C = parseInt(m[1] || "0", 10);
      H = parseInt(m[2] || "0", 10);
      M = parseInt(m[3] || "0", 10);
      L = parseInt(m[4] || "0", 10);
      return { C, H, M, L };
    }

    const counts = getCounts();
    const C = counts.C, H = counts.H, M = counts.M, L = counts.L;
    const max = Math.max(C, H, M, L, 1);

    function hPct(v) {
      let p = Math.round((v / max) * 100);
      if (v > 0 && p < 10) p = 10;   // nếu có số thì ít nhất 10% để nhìn thấy
      if (p < 0) p = 0;
      if (p > 100) p = 100;
      return p;
    }

    console.log("[SB][sev] C/H/M/L =", C, H, M, L, "max =", max);

    // 2) Tìm heading "SEVERITY BUCKETS"
    const heading = Array.from(document.querySelectorAll("div, h1, h2, h3")).find(el => {
      const t = el.textContent || "";
      return /SEVERITY\s*BUCKETS/i.test(t);
    });
    if (!heading) {
      console.warn("[SB][sev] Không thấy heading 'SEVERITY BUCKETS'");
      return;
    }

    // 3) Tìm card bao quanh (sb-card hoặc card)
    let card = heading;
    while (card && card.parentElement &&
           !card.classList.contains("sb-card") &&
           !card.classList.contains("card")) {
      card = card.parentElement;
    }
    if (!card || card === document.body) {
      // fallback: dùng parent trực tiếp của heading
      card = heading.parentElement || heading;
    }

    // 4) Ẩn legend text cũ bên trong card (Critical/High/Medium/Low)
    const innerDivs = Array.from(card.querySelectorAll("div, span, p"));
    innerDivs.forEach(el => {
      if (el === heading) return;
      const t = (el.textContent || "").replace(/\s+/g, " ").trim();
      if (!t) return;

      const hasCrit = /Critical/i.test(t);
      const hasHigh = /High/i.test(t);
      const hasMed  = /Medium/i.test(t);
      const hasLow  = /Low/i.test(t);

      // Legend hàng ngang "Critical 0 High 170 Medium 8891 Low 10"
      if (hasCrit && hasHigh && hasMed && hasLow) {
        el.style.display = "none";
      }
    });

    // 5) Xoá chart cũ (nếu script trước đã vẽ)
    card.querySelectorAll(".sb-sev-vert-chart-safe, .sb-sev-vert-chart").forEach(el => el.remove());

    // 6) Vẽ chart cột đứng mới
    const chart = document.createElement("div");
    chart.className = "sb-sev-vert-chart-safe";

    const barsWrap = document.createElement("div");
    barsWrap.className = "sb-sev-vert-bars-safe";

    const defs = [
      { key: "critical", label: "Critical", value: C },
      { key: "high",     label: "High",     value: H },
      { key: "medium",   label: "Medium",   value: M },
      { key: "low",      label: "Low",      value: L }
    ];

    defs.forEach(cfg => {
      const col = document.createElement("div");
      col.className = "sb-sev-vert-col-safe";

      const bar = document.createElement("div");
      bar.className = "sb-sev-vert-bar-safe " + cfg.key;
      bar.style.height = hPct(cfg.value) + "%";
      bar.title = cfg.label + ": " + cfg.value;

      const label = document.createElement("div");
      label.className = "sb-sev-vert-label-safe";
      label.textContent = cfg.label;

      const value = document.createElement("div");
      value.className = "sb-sev-vert-value-safe";
      value.textContent = String(cfg.value);

      col.appendChild(bar);
      col.appendChild(label);
      col.appendChild(value);
      barsWrap.appendChild(col);
    });

    chart.appendChild(barsWrap);
    card.appendChild(chart);

    console.log("[SB][sev] Đã vẽ 4 cột đứng SEVERITY BUCKETS.");
  } catch (e) {
    console.warn("[SB][sev] Lỗi khi patch severity chart:", e);
  }
});
""").lstrip()

path.write_text(code, encoding="utf-8")
print(f"[OK] Đã ghi {path}")
PY

echo "[DONE] patch_sb_severity_chart_final_safe_v3.sh hoàn thành."
