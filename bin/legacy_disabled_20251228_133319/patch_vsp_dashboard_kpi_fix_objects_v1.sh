#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$ROOT/templates/vsp_dashboard_2025.html"
BACKUP="$TPL.bak_fix_objects_$(date +%Y%m%d_%H%M%S)"

echo "[BACKUP] $TPL -> $BACKUP"
cp "$TPL" "$BACKUP"

python - << 'PY'
import pathlib

tpl_path = pathlib.Path("templates/vsp_dashboard_2025.html")
txt = tpl_path.read_text(encoding="utf-8")

if "VSP_DASH_KPI_FIX_OBJECTS_V1" in txt:
    print("[PATCH] Đã có script fix objects – skip.")
    raise SystemExit(0)

marker = "</body>"
idx = txt.rfind(marker)
if idx == -1:
    raise SystemExit("[ERR] Không tìm thấy </body> trong template.")

snippet = """
  <script>
    // [VSP_DASH_KPI_FIX_OBJECTS_V1] Fix [object Object] cho Top CWE / Module
    (async function() {
      const LOG = "[VSP_DASH_KPI_FIX_OBJECTS_V1]";
      try {
        const res = await fetch("/api/vsp/dashboard_v3");
        if (!res.ok) {
          console.warn(LOG, "HTTP", res.status);
          return;
        }
        const data = await res.json();

        function fmtPrimitiveOrObject(v, type) {
          if (v == null) return "-";
          if (typeof v === "string" || typeof v === "number" || typeof v === "boolean") {
            return String(v);
          }
          // Nếu là object: ưu tiên các trường thường gặp
          try {
            if (type === "cwe") {
              if (v.code) return v.code;
              if (v.cwe) return v.cwe;
              if (v.id) return v.id;
              if (v.name) return v.name;
            } else if (type === "module") {
              if (v.name) return v.name;
              if (v.module) return v.module;
              if (v.package) return v.package;
              if (v.id) return v.id;
            }
          } catch (e) {}
          try {
            return JSON.stringify(v);
          } catch (e) {
            return "[object]";
          }
        }

        const topCweVal  = fmtPrimitiveOrObject(data.top_impacted_cwe, "cwe");
        const topModVal  = fmtPrimitiveOrObject(data.top_vulnerable_module, "module");

        // Tìm 2 card KPI có label tương ứng và sửa value
        const cards = document.querySelectorAll(".vsp-kpi-card");
        cards.forEach(function(card) {
          const labelEl = card.querySelector(".vsp-kpi-card__label");
          const valueEl = card.querySelector(".vsp-kpi-card__value");
          if (!labelEl || !valueEl) return;
          const label = (labelEl.textContent || "").trim().toLowerCase();
          if (label === "top cwe") {
            valueEl.textContent = topCweVal;
          } else if (label === "top vulnerable module") {
            valueEl.textContent = topModVal;
          }
        });
      } catch (e) {
        console.warn(LOG, "Error", e);
      }
    })();
  </script>
"""

txt = txt[:idx] + snippet + "\n" + txt[idx:]
tpl_path.write_text(txt, encoding="utf-8")
print("[PATCH] Đã inject script fix Top CWE / Module.")
PY
