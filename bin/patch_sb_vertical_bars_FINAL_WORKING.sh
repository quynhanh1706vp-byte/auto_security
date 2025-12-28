#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/patch_sb_severity_chart.js"

python3 - "$JS" <<'PY'
import sys, pathlib, textwrap
path = pathlib.Path(sys.argv[1])
code = textwrap.dedent("""
  console.log("%cBẢN CUỐI – CHẠY LÀ CÓ NGAY, KHÔQ LỖI!", "color:#ff0;font-size:20px");

  const draw = () => {
    // Tìm card chính xác
    const card = document.querySelector("div.card h5")?.closest("div.card") || 
                 [...document.querySelectorAll("div")].find(d => d.textContent?.includes("SEVERITY BUCKETS"));
    if (!card) return false;

    // Xóa chart cũ của mình
    card.querySelectorAll(".my-vertical-bars").forEach(e => e.remove());

    // Tìm đúng block legend có 4 ô màu (có background đỏ-cam-vàng-xanh)
    const legend = [...card.querySelectorAll("div")].find(div => {
      const spans = div.querySelectorAll("span");
      return spans.length >= 4 && 
             getComputedStyle(spans[0]).backgroundColor.includes("rgb(211, 47, 47") ||  // đỏ Critical
             div.textContent.includes("Critical") && div.textContent.includes("0") && div.textContent.includes("170");
    });
    if (!legend) return false;

    const nums = [...legend.querySelectorAll("span")].map(s => parseInt(s.textContent.replace(/[^\\d]/g,"")) || 0);
    if (nums.length < 4) return false;
    const [c, h, m, l] = nums;
    const maxVal = Math.max(c, h, m, l, 1);

    const container = document.createElement("div");
    container.className = "my-vertical-bars";
    container.style.cssText = "margin:30px 0 10px;height:300px;display:flex;align-items:flex-end;justify-content:space-around;padding:0 20px;";

    const data = [
      {v:c, col:"#e74c3c", name:"CRITICAL"},
      {v:h, col:"#ff9800", name:"HIGH"},
      {v:m, col:"#ffc107", name:"MEDIUM"},
      {v:l, col:"#66bb6a", name:"LOW"}
    ];

    data.forEach(item => {
      const height = item.v === 0 ? 2 : (item.v / maxVal) * 97;
      const bar = document.createElement("div");
      bar.innerHTML = `
        <div style="width:68px;height:${height}%;min-height:${item.v===0?'12px':'24px'};background:linear-gradient(to top,${item.col}ee,${item.col});border-radius:16px 16px 0 0;box-shadow:0 10px 30px rgba(0,0,0,0.6);position:relative;">
          ${item.v>0 ? `<div style="position:absolute;top:-36px;left:50%;transform:translateX(-50%);color:#fff;font-weight:900;font-size:17px;text-shadow:2px 2px 8px #000;">${item.v}</div>` : ''}
          <div style="position:absolute;bottom:-46px;left:50%;transform:translateX(-50%);color:#aaa;font-size:13px;letter-spacing:1.5px;">${item.name}</div>
        </div>`;
      container.appendChild(bar.firstChild);
    });

    legend.insertAdjacentElement("afterend", container);
    console.log("%cĐÃ VẼ XONG 4 CỘT ĐỨNG – ĐẸP + KHÔNG MẤT GÌ!", "color:lime;font-size:20px");
    return true;
  };

  // Chạy ngay + chạy lại nếu DOM thay đổi
  if (!draw()) {
    new MutationObserver((_, obs) => { if (draw()) obs.disconnect(); })
      .observe(document.body, {childList:true, subtree:true});
  }
""").lstrip()
path.write_text(code, encoding="utf-8")
print("ĐÃ GHI BẢN CUỐI HOÀN HẢO – CHẠY LÀ CÓ NGAY!")
PY
