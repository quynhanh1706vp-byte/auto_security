#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/patch_sb_severity_chart.js"

python3 - "$JS" <<'PY'
import sys, pathlib, textwrap
path = pathlib.Path(sys.argv[1])

code = textwrap.dedent("""
/**
 * patch_sb_severity_chart.js – PHIÊN BẢN ĐÚNG TỈ LỆ 100% (v2)
 * - Giữ legend gốc (4 box màu + số).
 * - Xoá mọi bar/chart cũ trong card.
 * - Vẽ lại 1 thanh ratio ngang, tỉ lệ chính xác theo C/H/M/L.
 */
document.addEventListener("DOMContentLoaded", () => {
  try {
    // 1) Tìm đúng card SEVERITY BUCKETS
    const card = Array.from(document.querySelectorAll(".sb-card, .card, .panel"))
      .find(el => el.textContent && /SEVERITY\\s*BUCKETS/i.test(el.textContent));
    if (!card) {
      console.warn("[SB][ratio] Không tìm thấy card 'SEVERITY BUCKETS'");
      return;
    }

    // 2) Xoá mọi bar/chart cũ trong card (do template hoặc patch cũ vẽ ra)
    card.querySelectorAll(".sb-buckets-chart-new, .sb-severity-bar, .progress, .progress-bar")
      .forEach(el => el.remove());

    // 3) Lấy legend đầu tiên có đủ Critical / High / Medium / Low
    const legend = Array.from(card.querySelectorAll("div")).find(div => {
      const t = div.textContent || "";
      return /Critical/.test(t) && /High/.test(t) && /Medium/.test(t) && /Low/.test(t);
    });
    if (!legend) {
      console.warn("[SB][ratio] Không tìm được legend Critical/High/Medium/Low");
      return;
    }

    // 4) Rút 4 số đầu tiên từ legend
    const nums = (legend.textContent || "").match(/\\d+/g);
    if (!nums || nums.length < 4) {
      console.warn("[SB][ratio] Không parse được 4 số C/H/M/L từ legend:", legend.textContent);
      return;
    }
    const [c, h, m, l] = nums.slice(0, 4).map(Number);
    const total = c + h + m + l || 1;

    const per = v => total > 0 ? (v / total) * 100 : 0;

    const percentages = {
      critical: per(c),
      high:     per(h),
      medium:   per(m),
      low:      per(l)
    };

    // 5) Tạo 1 thanh ratio ngang duy nhất
    const bar = document.createElement("div");
    bar.className = "sb-severity-bar";
    bar.style.cssText = [
      "height:20px",
      "border-radius:10px",
      "overflow:hidden",
      "margin:16px 0 8px",
      "display:flex",
      "width:100%",
      "box-shadow:0 2px 4px rgba(0,0,0,0.2)"
    ].join(";");

    const colors = {
      critical: "#d32f2f",
      high:     "#ff9800",
      medium:   "#ffc107",
      low:      "#4caf50"
    };
    const order = ["critical","high","medium","low"];

    order.forEach(key => {
      const raw = key === "critical" ? c : key === "high" ? h : key === "medium" ? m : l;
      let pct = percentages[key];
      if (pct < 0.1) return; // quá nhỏ thì bỏ, tránh lằn 0.01px

      const seg = document.createElement("div");
      seg.style.cssText = [
        "flex:" + pct,
        "background:" + colors[key],
        pct < 1 ? "min-width:2px" : ""
      ].filter(Boolean).join(";");
      seg.title = key.toUpperCase() + ": " + raw + " (" + pct.toFixed(2) + "%)";
      bar.appendChild(seg);
    });

    // 6) Chèn thanh ratio ngay dưới legend
    legend.insertAdjacentElement("afterend", bar);

    console.log("[SB][ratio] Đã vẽ lại bar đúng tỉ lệ:", percentages);
  } catch(e) {
    console.warn("[SB][ratio] Lỗi patch ratio:", e);
  }
});
""").lstrip()

path.write_text(code, encoding="utf-8")
print(f"[OK] Đã ghi {path} – bar ratio sẽ đúng tỉ lệ C/H/M/L")
PY

echo "[DONE] patch_sb_severity_chart_correct_ratio_v2.sh – hãy restart UI và F5 Dashboard."
