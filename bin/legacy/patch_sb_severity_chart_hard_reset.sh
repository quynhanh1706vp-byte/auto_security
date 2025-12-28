#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/patch_sb_severity_chart.js"
CSS="$ROOT/static/css/security_resilient.css"

echo "[i] ROOT = $ROOT"
echo "[i] Ghi đè $JS – hard reset SEVERITY BUCKETS -> 4 cột đứng."

python3 - "$JS" <<'PY'
import sys, pathlib, textwrap
path = pathlib.Path(sys.argv[1])

code = textwrap.dedent("""
/**
 * patch_sb_severity_chart.js – HARD RESET
 * - Lấy C/H/M/L từ:
 *    1) RUN OVERVIEW: 'Totals: ... (C=..., H=..., M=..., L=...)'
 *    2) Nếu fail: chính text trong card SEVERITY BUCKETS (Critical 0 High 170...)
 * - Tìm card chứa chữ 'SEVERITY BUCKETS'
 * - XÓA toàn bộ innerHTML của card
 * - Vẽ lại title + 4 cột đứng Critical / High / Medium / Low
 */
document.addEventListener("DOMContentLoaded", function () {
  try {
    function getCounts() {
      let C = 0, H = 0, M = 0, L = 0;

      // 1) Thử lấy từ RUN OVERVIEW
      const totalsNode = Array.from(document.querySelectorAll("div, span, p")).find(el => {
        const t = el.textContent || "";
        return /Totals:/i.test(t) && /C\\s*=\\s*\\d+/i.test(t) && /H\\s*=\\s*\\d+/i.test(t)
               && /M\\s*=\\s*\\d+/i.test(t) && /L\\s*=\\s*\\d+/i.test(t);
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

      // 2) Fallback: lấy từ chính card SEVERITY BUCKETS (Critical 0 High 170 Medium 8891 Low 10)
      const sevCardTextNode = Array.from(document.querySelectorAll("div")).find(el => {
        const t = el.textContent || "";
        return /SEVERITY\\s*BUCKETS/i.test(t) && /Critical/i.test(t) && /High/i.test(t)
               && /Medium/i.test(t) && /Low/i.test(t);
      });

      if (sevCardTextNode) {
        const nums = (sevCardTextNode.textContent || "").match(/\\d+/g);
        if (nums && nums.length >= 4) {
          C = parseInt(nums[0], 10) || 0;
          H = parseInt(nums[1], 10) || 0;
          M = parseInt(nums[2], 10) || 0;
          L = parseInt(nums[3], 10) || 0;
          return { C, H, M, L };
        }
      }

      console.warn("[SB][hard] Không lấy được C/H/M/L – trả về 0 hết.");
      return { C:0, H:0, M:0, L:0 };
    }

    const counts = getCounts();
    const C = counts.C, H = counts.H, M = counts.M, L = counts.L;
    const max = Math.max(C, H, M, L, 1);

    function hPct(v) {
      let p = Math.round((v / max) * 100);
      if (v > 0 && p < 10) p = 10;   // có số thì ít nhất 10%
      if (p < 0) p = 0;
      if (p > 100) p = 100;
      return p;
    }

    console.log("[SB][hard] C/H/M/L =", C, H, M, L, "max =", max);

    // 3) Tìm card SEVERITY BUCKETS
    const sevCard = Array.from(document.querySelectorAll("div")).find(el => {
      const t = el.textContent || "";
      return /SEVERITY\\s*BUCKETS/i.test(t);
    });
    if (!sevCard) {
      console.warn("[SB][hard] Không tìm thấy card 'SEVERITY BUCKETS'");
      return;
    }

    // 4) ĐÈ innerHTML: title + chart mới
    sevCard.innerHTML = "";

    const title = document.createElement("div");
    title.className = "sb-sev-title";
    title.textContent = "SEVERITY BUCKETS";
    sevCard.appendChild(title);

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
    sevCard.appendChild(chart);

    console.log("[SB][hard] Đã vẽ 4 cột đứng SEVERITY BUCKETS.");
  } catch (e) {
    console.warn("[SB][hard] Lỗi khi patch severity chart:", e);
  }
});
""").lstrip()

path.write_text(code, encoding="utf-8")
print(f"[OK] Đã ghi {path}")
PY

# CSS cho phần mới
python3 - "$CSS" <<'PY'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
css = path.read_text(encoding="utf-8")

marker = "/* [sb_severity_column_hard_reset] */"
if marker in css:
    print("[i] CSS đã có sb_severity_column_hard_reset – bỏ qua.")
else:
    extra = """
/* [sb_severity_column_hard_reset] Title + cột đứng */
.sb-sev-title {
  font-size: 14px;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  margin-bottom: 12px;
}

.sb-sev-vert-chart {
  margin-top: 0;
  padding-top: 0;
}

.sb-sev-vert-bars {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 16px;
  height: 120px;
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
    print("[OK] Đã append CSS sb_severity_column_hard_reset")
PY

echo "[DONE] patch_sb_severity_chart_hard_reset.sh hoàn thành."
