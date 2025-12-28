#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/patch_sb_severity_chart.js"

python3 - "$JS" <<'PY'
import sys, pathlib, textwrap
path = pathlib.Path(sys.argv[1])
code = textwrap.dedent("""
  document.addEventListener("DOMContentLoaded", () => {
    try {
      // Tìm card SEVERITY BUCKETS
      const card = Array.from(document.querySelectorAll("div")).find(el => 
        el.textContent && /SEVERITY\\s*BUCKETS/i.test(el.textContent)
      );
      if (!card) return;

      // Xóa mọi chart cũ
      card.querySelectorAll(".sb-severity-bar, .sb-vertical-bars").forEach(el => el.remove());

      // Tìm legend chứa 4 số
      const legend = Array.from(card.querySelectorAll("div")).find(div => {
        const t = (div.textContent || "").replace(/\\s+/g, " ");
        return /Critical/i.test(t) && /High/i.test(t) && /Medium/i.test(t) && /Low/i.test(t);
      });
      if (!legend) return;

      const nums = (legend.textContent || "").match(/\\d+/g);
      if (!nums || nums.length < 4) return;
      const [c, h, m, l] = nums.map(Number);
      const total = c + h + m + l || 1;
      const maxVal = Math.max(c, h, m, l, 1);

      // Tạo container cho biểu đồ cột đứng
      const container = document.createElement("div");
      container.className = "sb-vertical-bars";
      container.style.cssText = `
        margin: 20px 0 10px;
        height: 260px;
        display: flex;
        align-items: flex-end;
        justify-content: space-around;
        padding: 0 20px;
        position: relative;
      `;

      const levels = [
        { name: "Critical", val: c, color: "#d32f2f", label: "CRITICAL" },
        { name: "High",     val: h, color: "#ff9800", label: "HIGH" },
        { name: "Medium",   val: m, color: "#ffc107", label: "MEDIUM" },
        { name: "Low",      val: l, color: "#66bb6a", label: "LOW" }
      ];

      levels.forEach(level => {
        const pct = (level.val / maxVal) * 100;
        const height = level.val === 0 ? 1.5 : Math.max(pct, 2); // ít nhất 2% nếu có giá trị

        const bar = document.createElement("div");
        bar.style.cssText = `
          width: 60px;
          height: ${height}%;
          min-height: ${level.val === 0 ? "6px" : "12px"};
          background: ${level.color};
          border-radius: 8px 8px 0 0;
          position: relative;
          box-shadow: 0 4px 12px rgba(0,0,0,0.3);
          transition: all 0.4s ease;
          background: linear-gradient(to top, ${level.color}dd, ${level.color});
        `;

        // Số lượng trên đầu cột (nếu > 0)
        if (level.val > 0) {
          const label = document.createElement("div");
          label.textContent = level.val.toLocaleString();
          label.style.cssText = `
            position: absolute;
            top: -26px;
            left: 50%;
            transform: translateX(-50%);
            color: white;
            font-weight: bold;
            font-size: 14px;
            text-shadow: 0 0 8px black;
          `;
          bar.appendChild(label);
        }

        // Tên severity dưới cột
        const title = document.createElement("div");
        title.textContent = level.label;
        title.style.cssText = `
          position: absolute;
          bottom: -36px;
          left: 50%;
          transform: translateX(-50%);
          color: #aaa;
          font-size: 12px;
          text-transform: uppercase;
          letter-spacing: 1px;
          white-space: nowrap;
        `;
        bar.appendChild(title);

        // Tooltip khi hover
        bar.title = `${level.name}: ${level.val} findings`;

        container.appendChild(bar);
      });

      // Chèn ngay dưới legend
      legend.insertAdjacentElement("afterend", container);

      console.log("[SB] Biểu đồ cột đứng ĐẸP NHƯ ẢNH đã được vẽ thành công!");
    } catch (e) {
      console.warn("[SB] Lỗi patch vertical bars:", e);
    }
  });
""").lstrip()

path.write_text(code, encoding="utf-8")
print("[OK] ĐÃ GHI FILE – BIỂU ĐỒ CỘT ĐỨNG SIÊU ĐẸP NHƯ ẢNH BẠN MUỐN!")
PY

echo "=== HOÀN TẤT! Reload trang là thấy ngay 4 cột đứng đẹp như ảnh bạn edit ==="
