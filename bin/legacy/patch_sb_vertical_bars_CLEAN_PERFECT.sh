#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/patch_sb_severity_chart.js"

python3 - "$JS" <<'PY'
import sys, pathlib, textwrap
path = pathlib.Path(sys.argv[1])
code = textwrap.dedent("""
  // FINAL CLEAN & PERFECT VERTICAL BARS – KHÔNG CÒN LỖI GIAO DIỆN
  console.log("%cFINAL CLEAN VERTICAL BARS – SẠCH ĐẸP 100%", "color:lime;font-size:18px");

  const run = () => {
    const card = [...document.querySelectorAll("div")].find(el => 
      el.textContent && /SEVERITY\\s*BUCKETS/i.test(el.textContent)
    );
    if (!card) return false;

    // 1. XÓA SẠCH mọi thứ cũ (cả thanh ngang lẫn cột cũ)
    card.querySelectorAll(".sb-severity-bar, .ultimate-vertical-bars, .sb-vertical-bars, .progress, .progress-bar").forEach(e => e.remove());

    // 2. ẨN/HIDE luôn 2 block thừa (dòng số thứ 2 và thanh ngang gốc nếu có)
    [...card.querySelectorAll("div")].forEach(div => {
      const t = (div.textContent||"").replace(/\\s+/g," ");
      if (/Critical.*High.*Medium.*Low/i.test(t) && !div.querySelector("canvas,svg")) {
        if (div.innerHTML.includes("C=0") || div.innerHTML.includes("C=,")) {
          div.style.display = "none"; // ẩn dòng C=0,H=170,... thứ 2
        }
      }
    });

    // 3. Tìm legend chính (block có 4 ô màu + số)
    const legend = [...card.querySelectorAll("div")].find(div => {
      const t = (div.textContent||"");
      return /Critical/i.test(t) && /High/i.test(t) && /Medium/i.test(t) && /Low/i.test(t) && t.match(/\\d+/g)?.length >= 4;
    });
    if (!legend) return false;

    const nums = legend.textContent.match(/\\d+/g);
    const [c,h,m,l] = nums.map(Number);
    const maxVal = Math.max(c,h,m,l,1);

    const container = document.createElement("div");
    container.style.cssText = "margin:35px auto 15px;height:310px;display:flex;align-items:flex-end;justify-content:center;gap:40px;padding:0 20px;";

    const levels = [
      {v:c, col:"#e74c3c", name:"CRITICAL"},
      {v:h, col:"#ff9800", name:"HIGH"},
      {v:m, col:"#ffc107", name:"MEDIUM"},
      {v:l, col:"#66bb6a", name:"LOW"}
    ];

    levels.forEach(lv => {
      const h = lv.v === 0 ? 2.2 : (lv.v / maxVal) * 98;
      const bar = document.createElement("div");
      bar.innerHTML = `
        <div style="width:68px;height:${h}%;min-height:${lv.v===0?'12px':'24px'};background:linear-gradient(to top,${lv.col}ee,${lv.col});border-radius:16px 16px 0 0;box-shadow:0 12px 32px rgba(0,0,0,0.55);position:relative;transition:all .6s;">
          ${lv.v>0 ? `<div style="position:absolute;top:-38px;left:50%;transform:translateX(-50%);color:#fff;font-weight:900;font-size:18px;text-shadow:2px 2px 10px #000;white-space:nowrap;">${lv.v.toLocaleString()}</div>` : ''}
          <div style="position:absolute;bottom:-50px;left:50%;transform:translateX(-50%);color:#ccc;font-size:14px;letter-spacing:2px;font-weight:600;">${lv.name}</div>
        </div>`;
      container.appendChild(bar.firstChild);
    });

    legend.insertAdjacentElement("afterend", container);
    console.log("%cĐÃ HOÀN HẢO – KHÔNG CÒN LỖI GIAO DIỆN!", "color:cyan;font-size:22px");
    return true;
  };

  if (!run()) {
    const mo = new MutationObserver(() => { if (run()) mo.disconnect(); });
    mo.observe(document.body, {childList:true, subtree:true});
  }
""").lstrip()
path.write_text(code, encoding="utf-8")
print("ĐÃ GHI BẢN CLEAN PERFECT – KHÔNG CÒN LỖI GIAO DIỆN!")
PY
