#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$ROOT/templates/vsp_dashboard_2025.html"
BACKUP="$TPL.bak_charts_tools_cwe_$(date +%Y%m%d_%H%M%S)"

echo "[BACKUP] $TPL -> $BACKUP"
cp "$TPL" "$BACKUP"

python - << 'PY'
import pathlib

tpl_path = pathlib.Path("templates/vsp_dashboard_2025.html")
txt = tpl_path.read_text(encoding="utf-8")

if "VSP_DASH_CHARTS_TOOLS_CWE_V1" in txt:
    print("[PATCH] Charts tools/CWE đã tồn tại – skip.")
    raise SystemExit(0)

marker = "</body>"
idx = txt.rfind(marker)
if idx == -1:
    raise SystemExit("[ERR] Không tìm thấy </body> trong template.")

snippet = """
  <script>
    // [VSP_DASH_CHARTS_TOOLS_CWE_V1] Charts 3 & 4: by tool + top CWE từ /api/vsp/datasource_v2
    (async function () {
      const LOG = "[VSP_DASH_CHARTS_TOOLS_CWE_V1]";
      try {
        const res = await fetch("/api/vsp/datasource_v2?limit=5000");
        if (!res.ok) {
          console.warn(LOG, "HTTP", res.status);
          return;
        }
        const data = await res.json();
        const items = Array.isArray(data)
          ? data
          : (Array.isArray(data.items) ? data.items : []);

        if (!items.length) {
          console.warn(LOG, "Không có items trong datasource.");
          return;
        }

        // Đếm theo tool & CWE
        const byTool = {};
        const byCwe  = {};

        items.forEach(function (it) {
          try {
            const tool = it.tool || it.tool_name || "unknown";
            const cweRaw = it.cwe || it.cwe_id || it.cwe_code || it.cwe_name;
            const cwe = cweRaw || "N/A";

            byTool[tool] = (byTool[tool] || 0) + 1;
            byCwe[cwe]   = (byCwe[cwe]   || 0) + 1;
          } catch (e) {
            // skip lỗi nhỏ
          }
        });

        function topN(obj, n) {
          return Object.entries(obj)
            .sort((a, b) => b[1] - a[1])
            .slice(0, n);
        }

        const topTools = topN(byTool, 5);
        const topCwes  = topN(byCwe, 5);

        const chartsRoot = document.getElementById("vsp-dashboard-charts-root");
        if (!chartsRoot) {
          console.warn(LOG, "Không thấy #vsp-dashboard-charts-root");
          return;
        }

        function fmt(v) {
          const n = Number(v);
          if (Number.isFinite(n)) return n.toLocaleString();
          return String(v ?? "0");
        }

        function buildBarPanel(title, entries, cssClass) {
          const panel = document.createElement("div");
          panel.className = "vsp-panel";
          panel.innerHTML = '<div class="vsp-panel-title">' + title + '</div>';

          const wrap = document.createElement("div");
          wrap.className = "vsp-chart-rows";

          let max = 0;
          entries.forEach(function ([k, v]) {
            if (v > max) max = v;
          });
          function w(v) {
            if (!max) return 0;
            return Math.max(8, (v / max) * 100);
          }

          entries.forEach(function ([k, v]) {
            const row = document.createElement("div");
            row.className = "vsp-chart-row";

            const label = document.createElement("div");
            label.className = "vsp-chart-row-label";
            label.textContent = k;

            const bar = document.createElement("div");
            bar.className = "vsp-chart-row-bar";
            const inner = document.createElement("div");
            inner.className = "vsp-chart-row-bar-inner " + (cssClass || "");
            inner.style.width = w(v) + "%";
            bar.appendChild(inner);

            const val = document.createElement("div");
            val.className = "vsp-chart-row-value";
            val.textContent = fmt(v);

            row.appendChild(label);
            row.appendChild(bar);
            row.appendChild(val);
            wrap.appendChild(row);
          });

          panel.appendChild(wrap);
          return panel;
        }

        // Panel 3: Findings by tool
        if (topTools.length) {
          const pTools = buildBarPanel("Findings by tool", topTools, "vsp-chart-sev-high");
          chartsRoot.appendChild(pTools);
        }

        // Panel 4: Top CWE exposure
        if (topCwes.length) {
          const pCwe = buildBarPanel("Top CWE exposure", topCwes, "vsp-chart-sev-medium");
          chartsRoot.appendChild(pCwe);
        }

      } catch (e) {
        console.warn(LOG, "Error", e);
      }
    })();
  </script>
"""

txt = txt[:idx] + snippet + "\\n" + txt[idx:]
tpl_path.write_text(txt, encoding="utf-8")
print("[PATCH] Đã inject charts by tool / top CWE.")
PY
