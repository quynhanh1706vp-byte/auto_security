#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/patch_sb_severity_chart.js"

python3 - "$JS" <<'PY'
import sys, pathlib, textwrap
path = pathlib.Path(sys.argv[1])
code = textwrap.dedent("""
  // VERTICAL BARS – FINAL PERFECT EDITION 2025-11-26
  console.log("%cVERTICAL BARS FINAL ĐÃ CHẠY – SẮP ĐẸP NHƯ ẢNH BẠN MUỐN!", "color:#0f0;font-size:18px");

  document.addEventListener("DOMContentLoaded", () => {
    setTimeout(() => {
      try {
        const card = [...document.querySelectorAll("div")].find(el => /SEVERITY\\s*BUCKETS/i.test(el.textContent || ""));
        if (!card) return;

        // Xóa sạch cũ
        card.querySelectorAll(".sb-vertical-bars,.sb-severity-bar").forEach(e=>e.remove());

        const legend = [...card.querySelectorAll("div")].find(d => /Critical.*High.*Medium.*Low/i.test(d.textContent || ""));
        if (!legend) return;
        const nums = (legend.textContent || "").match(/\\d+/g);
        if (!nums) return;
        const [c,h,m,l] = nums.map(Number);
        const total = c+h+m+l;
        const maxVal = Math.max(c,h,m,l,1);

        const container = document.createElement("div");
        container.className = "sb-vertical-bars";
        container.style.cssText = "margin:30px 0 10px;height:300px;display:flex;align-items:flex-end;justify-content:space-around;padding:0 40px;";

        const levels = [
          {name:"Critical", val:c, color:"#e74c3c", label:"CRITICAL"},
          {name:"High",     val:h, color:"#ff9800", label:"HIGH"},
          {name:"Medium",   val:m, color:"#ffc107", label:"MEDIUM"},
          {name:"Low",      val:l, color:"#66bb6a", label:"LOW"}
        ];

        levels.forEach(lv => {
          const ratio = lv.val / maxVal;
          const heightPct = lv.val === 0 ? 1.8 : (ratio * 100);

          const bar = document.createElement("div");
          bar.style.cssText = `
            width:70px;
            height:${heightPct}%;
            min-height:${lv.val===0?"10px":"20px"};
            background:linear-gradient(to top, ${lv.color}cc, ${lv.color});
            border-radius:14px 14px 0 0;
            position:relative;
            box-shadow:0 10px 25px rgba(0,0,0,0.5);
            transition:all 0.6s cubic-bezier(0.22,1,0.36,1);
          `;

          if (lv.val > 0) {
            const num = document.createElement("div");
            num.textContent = lv.val.toLocaleString();
            num.style.cssText = "position:absolute;top:-34px;left:50%;transform:translateX(-50%);color:#fff;font-weight:900;font-size:16px;text-shadow:2px 2px 8px #000;";
            bar.appendChild(num);
          }

          const title = document.createElement("div");
          title.textContent = lv.label;
          title.style.cssText = "position:absolute;bottom:-44px;left:50%;transform:translateX(-50%);color:#ddd;font-size:13px;letter-spacing:2px;font-weight:600;";
          bar.appendChild(title);

          container.appendChild(bar);
        });

        legend.insertAdjacentElement("afterend", container);
        console.log("%c4 CỘT ĐỨNG ĐÃ HOÀN HẢO – ĐẸP NHƯ ẢNH BẠN CHỈ!", "color:#ff0;font-size:20px");
      } catch(e) { console.error(e); }
    }, 800);
  });
""").lstrip()
path.write_text(code, encoding="utf-8")
print("ĐÃ GHI ĐÈ – BẢN FINAL ĐẸP NHƯ ẢNH!")
PY
