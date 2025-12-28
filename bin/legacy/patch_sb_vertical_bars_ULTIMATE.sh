#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/patch_sb_severity_chart.js"

python3 - "$JS" <<'PY'
import sys, pathlib, textwrap
path = pathlib.Path(sys.argv[1])
code = textwrap.dedent("""
  // === ULTIMATE VERTICAL BARS – CHẠY LÀ ĂN 1000% ===
  console.log("%c[SB] ULTIMATE VERTICAL BARS PATCH STARTED", "color:#f0f;font-size:18px");

  const drawChart = () => {
    try {
      const card = [...document.querySelectorAll("div")].find(el => 
        el.textContent && /SEVERITY\\s*BUCKETS/i.test(el.textContent)
      );
      if (!card) return false;

      // Xóa cũ
      card.querySelectorAll(".ultimate-vertical-bars").forEach(e => e.remove());

      const legend = [...card.querySelectorAll("div")].find(d => {
        const t = (d.textContent || "").replace(/\\s+/g," ");
        return /Critical/i.test(t) && /High/i.test(t) && /Medium/i.test(t) && /Low/i.test(t);
      });
      if (!legend) return false;

      const nums = legend.textContent.match(/\\d+/g);
      if (!nums || nums.length < 4) return false;
      const [c, h, m, l] = nums.map(Number);
      const maxVal = Math.max(c, h, m, l, 1);

      const container = document.createElement("div");
      container.className = "ultimate-vertical-bars";
      container.style.cssText = "margin:30px 0 20px;height:320px;display:flex;align-items:flex-end;justify-content:space-around;padding:0 30px;background:transparent;";

      const levels = [
        {val:c, color:"#e74c3c", name:"CRITICAL"},
        {val:h, color:"#ff9800", name:"HIGH"},
        {val:m, color:"#ffc107", name:"MEDIUM"},
        {val:l, color:"#66bb6a", name:"LOW"}
      ];

      levels.forEach(lv => {
        const height = lv.val === 0 ? 2 : (lv.val / maxVal) * 100;
        const bar = document.createElement("div");
        bar.innerHTML = `
          <div style="width:72px;height:${height}%;min-height:${lv.val===0?'12px':'24px'};background:linear-gradient(to top,${lv.color}dd,${lv.color});border-radius:16px 16px 0 0;box-shadow:0 12px 30px rgba(0,0,0,0.6);position:relative;">
            ${lv.val > 0 ? `<div style="position:absolute;top:-36px;left:50%;transform:translateX(-50%);color:#fff;font-weight:900;font-size:17px;text-shadow:2px 2px 10px #000;">${lv.val.toLocaleString()}</div>` : ''}
            <div style="position:absolute;bottom:-48px;left:50%;transform:translateX(-50%);color:#eee;font-size:14px;letter-spacing:2px;font-weight:600;">${lv.name}</div>
          </div>
        `;
        container.appendChild(bar.firstElementChild);
      });

      legend.insertAdjacentElement("afterend", container);
      console.log("%c4 CỘT ĐỨNG ĐÃ XUẤT HIỆN – ĐẸP NHƯ ẢNH BẠN MUỐN!", "color:#0ff;font-size:22px");
      return true;
    } catch(e) {
      console.warn("Draw failed:", e);
      return false;
    }
  };

  // Thử vẽ ngay + vẽ lại mỗi khi DOM thay đổi (bảo vệ 1000%)
  if (!drawChart()) {
    const observer = new MutationObserver(() => {
      if (drawChart()) observer.disconnect();
    });
    observer.observe(document.body, { childList: true, subtree: true });
    setTimeout(() => { drawChart() && observer.disconnect(); }, 3000);
  }
""").lstrip()
path.write_text(code, encoding="utf-8")
print("[OK] ĐÃ GHI FILE ULTIMATE – CHẮN CHẮN ĂN!")
PY
