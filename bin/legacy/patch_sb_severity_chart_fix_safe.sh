#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/patch_sb_severity_chart.js"
CSS="$ROOT/static/css/security_resilient.css"

echo "[i] ROOT = $ROOT"
echo "[i] Ghi đè $JS – vẽ 4 cột đứng, không xóa card."

python3 - "$JS" <<'PY'
import sys, pathlib, textwrap
path = pathlib.Path(sys.argv[1])

code = textwrap.dedent("""
/**
 * patch_sb_severity_chart.js – SAFE COLUMN
 * - Lấy C/H/M/L từ RUN OVERVIEW (Totals: ... (C=..., H=..., M=..., L=...)).
 * - Tìm card SEVERITY BUCKETS.
 * - Ẩn legend text bên trong card (Critical 0 High..., dòng C=...).
 * - Vẽ 4 cột đứng Critical / High / Medium / Low ở cuối card.
 * - KHÔNG đụng tới div bên ngoài card, KHÔNG innerHTML="".
 */
document.addEventListener("DOMContentLoaded", function () {
  try {
    // 1) Lấy số từ RUN OVERVIEW
    function getCounts() {
      let C = 0, H = 0, M = 0, L = 0;

      const totalsNode = Array.from(document.querySelectorAll("div, span, p")).find(el => {
        const t = el.textContent || "";
        return /Totals:/i.test(t) &&
               /C\\s*=\\s*\\d+/i.test(t) &&
               /H\\s*=\\s*\\d+/i.test(t) &&
               /M\\s*=\\s*\\d+/i.test(t) &&
               /L\\s*=\\s*\\d+/i.test(t);
      });

      if (totalsNode) {
        const txt = (totalsNode.textContent || "").replace(/\\s+/g, " ");
        const m = txt.match(/C\\s*=\\s*(\\d+)\\s*,\\s*H\\s*=\\s*(\\d+)\\s*,\\s*M\\s*=\\s*(\\d+)\\s*,\\s*L\\s*=\\s*(\\d+)/i);
        if (m) {
          C = parseInt(m[1] || "0", 10);
          H = parseInt(m[2] || "0", 10);
          M = parseInt(m[3] || "0", 10);
          L = parseInt(m[4] || "0", 10);
          return { C, H, M, L };
        }
      }

      console.warn("[SB][safe] Không lấy được C/H/M/L – trả về 0.");
      return { C:0, H:0, M:0, L:0 };
    }

    const { C, H, M, L } = getCounts();
    const max = Math.max(C, H, M, L, 1);

    function hPct(v) {
      let p = Math.round((v / max) * 100);
      if (v > 0 && p < 10) p = 10;   // có số thì ít nhất 10%
      if (p < 0) p = 0;
      if (p > 100) p = 100;
      return p;
    }

    console.log("[SB][safe] C/H/M/L =", C, H, M, L, "max =", max);

    // 2) Tìm card SEVERITY BUCKETS (chỉ trong các card/panel)
    const sevCard = Array.from(document.querySelectorAll(".sb-card, .card, .panel")).find(el => {
      const t = el.textContent || "";
      return /SEVERITY\\s*BUCKETS/i.test(t);
    });
    if (!sevCard) {
      console.warn("[SB][safe] Không tìm thấy card 'SEVERITY BUCKETS'");
      return;
    }

    // 3) Ẩn legend text bên trong card (chỉ các con của card)
    const innerDivs = Array.from(sevCard.querySelectorAll("div"));

    innerDivs.forEach(el => {
      const t = (el.textContent || "").replace(/\\s+/g, " ").trim();
      if (!t) return;

      // Legend Critical/High/Medium/Low
      const hasAll =
        t.indexOf("Critical") !== -1 &&
        t.indexOf("High")     !== -1 &&
        t.indexOf("Medium")   !== -1 &&
        t.indexOf("Low")      !== -1;

      // Dòng C=0, H=170, ...
      const isSummary = /C\\s*=\\s*\\d+.*H\\s*=\\s*\\d+.*M\\s*=\\s*\\d+.*L\\s*=\\s*\\d+/.test(t);

      if (hasAll || isSummary) {
        el.style.display = "none";
      }
    });

    // 4) Nếu đã có chart safe thì xoá để render lại
    const oldChart = sevCard.querySelector(".sb-sev-vert-chart-safe");
    if (oldChart) oldChart.remove();

    // 5) Tạo chart mới
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
    sevCard.appendChild(chart);

    console.log("[SB][safe] Đã vẽ 4 cột đứng cho SEVERITY BUCKETS.");
  } catch (e) {
    console.warn("[SB][safe] Lỗi khi patch severity chart:", e);
  }
});
""").lstrip()

path.write_text(code, encoding="utf-8")
print(f"[OK] Đã ghi {path}")
PY

# CSS an toàn cho chart mới (class riêng)
python3 - "$CSS" <<'PY'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
css = path.read_text(encoding="utf-8")

marker = "/* [sb_severity_column_safe] */"
if marker in css:
    print("[i] CSS đã có sb_severity_column_safe – bỏ qua.")
else:
    extra = """
/* [sb_severity_column_safe] Biểu đồ cột đứng SEVERITY BUCKETS */
.sb-sev-vert-chart-safe {
  margin-top: 12px;
  padding-top: 8px;
  border-top: 1px solid rgba(255,255,255,0.06);
}

.sb-sev-vert-bars-safe {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 16px;
  height: 120px;
}

.sb-sev-vert-col-safe {
  flex: 1;
  text-align: center;
  font-size: 11px;
}

.sb-sev-vert-bar-safe {
  width: 55%;
  margin: 0 auto 4px;
  border-radius: 4px;
  opacity: 0.95;
}

.sb-sev-vert-bar-safe.critical {
  background: linear-gradient(180deg, #ff4e50, #ff6a4d);
}
.sb-sev-vert-bar-safe.high {
  background: linear-gradient(180deg, #ffb347, #ffcc33);
}
.sb-sev-vert-bar-safe.medium {
  background: linear-gradient(180deg, #ffd866, #ffee99);
}
.sb-sev-vert-bar-safe.low {
  background: linear-gradient(180deg, #84e184, #a8ffb0);
}

.sb-sev-vert-label-safe {
  opacity: 0.8;
  margin-top: 0;
}

.sb-sev-vert-value-safe {
  opacity: 0.9;
}
"""
    css = css.rstrip() + "\\n" + extra + "\\n"
    path.write_text(css, encoding="utf-8")
    print("[OK] Đã append CSS sb_severity_column_safe")
PY

echo "[DONE] patch_sb_severity_chart_fix_safe.sh hoàn thành."
