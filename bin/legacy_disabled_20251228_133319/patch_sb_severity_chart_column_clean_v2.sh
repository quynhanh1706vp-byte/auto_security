#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/patch_sb_severity_chart.js"
CSS="$ROOT/static/css/security_resilient.css"

echo "[i] ROOT = $ROOT"
echo "[i] Ghi đè $JS – xóa legend ngang + C=... và vẽ biểu đồ cột đứng."

python3 - "$JS" <<'PY'
import sys, pathlib, textwrap

path = pathlib.Path(sys.argv[1])

code = textwrap.dedent("""
/**
 * patch_sb_severity_chart.js – COLUMN CLEAN v2
 * - Card SEVERITY BUCKETS:
 *   + Lấy số từ dòng summary: C=..., H=..., M=..., L=...
 *   + Ẩn mọi legend ngang + dòng summary đó.
 *   + Vẽ 4 cột đứng Critical / High / Medium / Low theo max(C,H,M,L).
 */
document.addEventListener("DOMContentLoaded", function () {
  try {
    // 1) Tìm card SEVERITY BUCKETS
    const cards = Array.from(document.querySelectorAll(".sb-card, .card, .panel"));
    const card = cards.find(el => {
      const t = el.textContent || "";
      return /SEVERITY\\s*BUCKETS/i.test(t);
    });
    if (!card) {
      console.warn("[SB][col v2] Không tìm thấy card 'SEVERITY BUCKETS'");
      return;
    }

    // 2) Tìm dòng summary kiểu 'C=0, H=170, M=8891, L=10'
    const summary = Array.from(card.querySelectorAll("*")).find(el => {
      const t = el.textContent || "";
      return /C=\\d+\\s*,\\s*H=\\d+\\s*,\\s*M=\\d+\\s*,\\s*L=\\d+/.test(t);
    });
    if (!summary) {
      console.warn("[SB][col v2] Không tìm thấy dòng summary C/H/M/L trong card");
      return;
    }

    const text = (summary.textContent || "").replace(/\\s+/g, " ");
    const m = text.match(/C=(\\d+).*H=(\\d+).*M=(\\d+).*L=(\\d+)/);
    if (!m) {
      console.warn("[SB][col v2] Không parse được C/H/M/L từ:", text);
      return;
    }

    const C = parseInt(m[1], 10) || 0;
    const H = parseInt(m[2], 10) || 0;
    const M = parseInt(m[3], 10) || 0;
    const L = parseInt(m[4], 10) || 0;
    const max = Math.max(C, H, M, L, 1);

    function hPct(v) {
      let p = Math.round((v / max) * 100);
      if (v > 0 && p < 10) p = 10; // có số thì ít nhất 10%
      if (p < 0) p = 0;
      if (p > 100) p = 100;
      return p;
    }

    console.log("[SB][col v2] C/H/M/L =", C, H, M, L, "max =", max);

    // 3) XÓA / ẨN legend ngang + chart cũ
    // 3.1. Ẩn mọi block có đủ Critical / High / Medium / Low (legend ngang)
    const blocks = Array.from(card.querySelectorAll("div"));
    blocks.forEach(el => {
      const t = (el.textContent || "").replace(/\\s+/g, " ");
      const hasAll =
        t.indexOf("Critical") !== -1 &&
        t.indexOf("High")     !== -1 &&
        t.indexOf("Medium")   !== -1 &&
        t.indexOf("Low")      !== -1;
      if (hasAll) {
        el.style.display = "none";
      }
    });

    // 3.2. Ẩn luôn dòng summary C=...,H=...,M=...,L=...
    summary.style.display = "none";

    // 3.3. Xóa chart do patch cũ vẽ ra (nếu còn)
    card.querySelectorAll(".sb-sev-vert-chart, .sb-buckets-chart-new, .sb-buckets-row-custom, .sb-severity-bar")
      .forEach(el => el.remove());

    // 4) Tạo container biểu đồ cột đứng mới
    const chart = document.createElement("div");
    chart.className = "sb-sev-vert-chart";

    const barsWrap = document.createElement("div");
    barsWrap.className = "sb-sev-vert-bars";

    const defs = [
      { key: "critical", label: "Critical", value: C },
      { key: "high",     label: "High",     value: H },
      { key: "medium",   label: "Medium",   value: M },
      { key: "low",      label: "Low",      value: L }
    ];

    defs.forEach(cfg => {
      const col = document.createElement("div");
      col.className = "sb-sev-vert-col";

      const bar = document.createElement("div");
      bar.className = "sb-sev-vert-bar " + cfg.key;
      bar.style.height = hPct(cfg.value) + "%";
      bar.title = cfg.label + ": " + cfg.value;

      const label = document.createElement("div");
      label.className = "sb-sev-vert-label";
      label.textContent = cfg.label;

      const value = document.createElement("div");
      value.className = "sb-sev-vert-value";
      value.textContent = String(cfg.value);

      col.appendChild(bar);
      col.appendChild(label);
      col.appendChild(value);
      barsWrap.appendChild(col);
    });

    chart.appendChild(barsWrap);

    // 5) Chèn chart vào cuối card (ngay dưới title)
    card.appendChild(chart);

    console.log("[SB][col v2] Đã render biểu đồ cột đứng mới.");
  } catch (e) {
    console.warn("[SB][col v2] Lỗi khi patch severity column chart:", e);
  }
});
""").lstrip()

path.write_text(code, encoding="utf-8")
print(f"[OK] Đã ghi {path}")
PY

# Thêm CSS cho biểu đồ cột đứng (nếu chưa có)
python3 - "$CSS" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
css = path.read_text(encoding="utf-8")

marker = "/* [sb_severity_column_clean_v2] */"
if marker in css:
    print("[i] CSS đã có sb_severity_column_clean_v2 – bỏ qua.")
else:
    extra = """
/* [sb_severity_column_clean_v2] Biểu đồ cột đứng SEVERITY BUCKETS */
.sb-sev-vert-chart {
  margin-top: 12px;
  padding-top: 8px;
  border-top: 1px solid rgba(255,255,255,0.06);
}

.sb-sev-vert-bars {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 16px;
  height: 120px; /* chiều cao vùng cột */
}

.sb-sev-vert-col {
  flex: 1;
  text-align: center;
  font-size: 11px;
}

.sb-sev-vert-bar {
  width: 55%;
  margin: 0 auto 4px;
  border-radius: 4px;
  opacity: 0.95;
}

/* Màu theo severity */
.sb-sev-vert-bar.critical {
  background: linear-gradient(180deg, #ff4e50, #ff6a4d);
}
.sb-sev-vert-bar.high {
  background: linear-gradient(180deg, #ffb347, #ffcc33);
}
.sb-sev-vert-bar.medium {
  background: linear-gradient(180deg, #ffd866, #ffee99);
}
.sb-sev-vert-bar.low {
  background: linear-gradient(180deg, #84e184, #a8ffb0);
}

.sb-sev-vert-label {
  opacity: 0.8;
  margin-top: 0;
}

.sb-sev-vert-value {
  opacity: 0.9;
}
"""
    css = css.rstrip() + "\\n" + extra + "\\n"
    path.write_text(css, encoding="utf-8")
    print("[OK] Đã append CSS sb_severity_column_clean_v2")
PY

echo "[DONE] patch_sb_severity_chart_column_clean_v2.sh hoàn thành."
