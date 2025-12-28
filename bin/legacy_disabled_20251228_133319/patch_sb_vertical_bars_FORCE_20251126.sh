#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/patch_sb_severity_chart.js"

python3 - "$JS" <<'PY'
import sys, pathlib, textwrap
path = pathlib.Path(sys.argv[1])
code = textwrap.dedent("""
  // === VERTICAL BARS PRO - FORCE 2025-11-26 ===
  console.log("%c SEVERITY VERTICAL BARS PATCH ĐÃ CHẠY LÚC " + new Date(), "color: lime; font-size: 16px; font-weight: bold");

  document.addEventListener("DOMContentLoaded", () => {
    setTimeout(() => {  // chạy trễ 1s để chắc chắn DOM đã load xong
      try {
        const card = [...document.querySelectorAll("div")].find(el => 
          el.textContent && /SEVERITY\\s*BUCKETS/i.test(el.textContent)
        );
        if (!card) return;

        // XÓA SẠCH mọi thứ cũ trước khi vẽ mới
        card.querySelectorAll(".sb-severity-bar, .sb-vertical-bars, .progress, .progress-bar").forEach(el => el.remove());

        const legend = [...card.querySelectorAll("div")].find(div => {
          const t = (div.textContent || "").replace(/\\s+/g," ");
          return /Critical/i.test(t) && /High/i.test(t) && /Medium/i.test(t) && /Low/i.test(t);
        });
        if (!legend) return;

        const nums = (legend.textContent || "").match(/\\d+/g);
        if (!nums || nums.length < 4) return;
        const [c, h, m, l] = nums.map(Number);
        const total = c + h + m + l || 1;
        const maxVal = Math.max(c, h, m, l, 1);

        const container = document.createElement("div");
        container.className = "sb-vertical-bars";
        container.style.cssText = "margin:24px 0;height:280px;display:flex;align-items:flex-end;justify-content:space-around;padding:0 30px;position:relative;";

        const levels = [
          {name:"Critical",val:c,color:"#e74c3c",label:"CRITICAL"},
          {name:"High",    val:h,color:"#ff9800",label:"HIGH"},
          {name:"Medium",  val:m,color:"#ffc107",label:"MEDIUM"},
          {name:"Low",     val:l,color:"#66bb6a",label:"LOW"}
        ];

        levels.forEach(lv => {
          const pct = (lv.val / maxVal) * 100;
          const height = lv.val === 0 ? 2 : Math.max(pct, 3);

          const bar = document.createElement("div");
          bar.style.cssText = `
            width:64px; height:${height}%; min-height:${lv.val===0?"8px":"16px"};
            background:linear-gradient(to top, ${lv.color}ee, ${lv.color});
            border-radius:12px 12px 0 0; position:relative;
            box-shadow:0 8px 20px rgba(0,0,0,0.4); transition:all 0.5s ease;
          `;

          if (lv.val > 0) {
            const num = document.createElement("div");
            num.textContent = lv.val.toLocaleString();
            num.style.cssText = "position:absolute;top:-30px;left:50%;transform:translateX(-50%);color:white;font-weight:bold;font-size:15px;text-shadow:0 0 10px black;";
            bar.appendChild(num);
          }

          const title = document.createElement("div");
          title.textContent = lv.label;
          title.style.cssText = "position:absolute;bottom:-40px;left:50%;transform:translateX(-50%);color:#ccc;font-size:13px;letter-spacing:1px;";
          bar.appendChild(title);

          bar.title = lv.name + ": " + lv.val;
          container.appendChild(bar);
        });

        legend.insertAdjacentElement("afterend", container);
        console.log("%c ĐÃ VẼ XONG 4 CỘT ĐỨNG ĐẸP NHƯ ẢNH!", "color: cyan; font-size: 18px");
      } catch(e) { console.error("Lỗi vertical bars:", e); }
    }, 1000);
  });
""").lstrip()
path.write_text(code, encoding="utf-8")
print("[OK] ĐÃ GHI ĐÈ FILE JS – BẢN CỘT ĐỨNG SIÊU ĐẸP 2025-11-26")
PY
