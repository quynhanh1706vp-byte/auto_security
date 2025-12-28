#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$ROOT/templates/vsp_dashboard_2025.html"
BACKUP="$TPL.bak_charts_v4_$(date +%Y%m%d_%H%M%S)"

echo "[BACKUP] $TPL -> $BACKUP"
cp "$TPL" "$BACKUP"

python - << 'PY'
import pathlib

tpl_path = pathlib.Path("templates/vsp_dashboard_2025.html")
txt = tpl_path.read_text(encoding="utf-8")

if "VSP_DASH_CHARTS_V4" in txt:
    print("[PATCH] V4 đã tồn tại – skip.")
    raise SystemExit(0)

marker = "</body>"
idx = txt.rfind(marker)
if idx == -1:
    raise SystemExit("[ERR] Không tìm thấy </body> trong template.")

snippet = """
  <script>
    // [VSP_DASH_CHARTS_V4] 4 chart: severity, top risk, by tool, top CWE
    (function () {
      const LOG = "[VSP_DASH_CHARTS_V4]";

      async function loadCharts() {
        try {
          // Gọi song song dashboard + datasource
          const [dashRes, dsRes] = await Promise.all([
            fetch("/api/vsp/dashboard_v3"),
            fetch("/api/vsp/datasource_v2?limit=5000")
          ]);

          if (!dashRes.ok) {
            console.warn(LOG, "dashboard_v3 HTTP", dashRes.status);
            return;
          }
          if (!dsRes.ok) {
            console.warn(LOG, "datasource_v2 HTTP", dsRes.status);
            return;
          }

          const dash = await dashRes.json();
          const dsRaw = await dsRes.json();

          const bySev = (dash && dash.by_severity) || {};
          const sevOrder = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];

          const items = Array.isArray(dsRaw)
            ? dsRaw
            : (Array.isArray(dsRaw.items) ? dsRaw.items : []);

          const chartsRoot = document.getElementById("vsp-dashboard-charts-root");
          if (!chartsRoot) {
            console.warn(LOG, "Không thấy #vsp-dashboard-charts-root");
            return;
          }
          // Xoá toàn bộ cái cũ (nếu script v1/v2 đã vẽ gì)
          chartsRoot.innerHTML = "";

          function fmt(v) {
            const n = Number(v);
            if (Number.isFinite(n)) return n.toLocaleString();
            return String(v ?? "0");
          }

          // ========== Chart 1: Severity distribution ==========
          let totalSev = 0;
          sevOrder.forEach(sev => { totalSev += Number(bySev[sev] || 0); });

          function widthPercent(v, total) {
            if (!total) return 0;
            return Math.max(6, (v / total) * 100);
          }

          const panelSev = document.createElement("div");
          panelSev.className = "vsp-panel";
          panelSev.innerHTML = '<div class="vsp-panel-title">Severity distribution</div>';

          const sevWrap = document.createElement("div");
          sevWrap.className = "vsp-chart-rows";

          sevOrder.forEach(sev => {
            const v = Number(bySev[sev] || 0);
            const row = document.createElement("div");
            row.className = "vsp-chart-row";

            const label = document.createElement("div");
            label.className = "vsp-chart-row-label";
            label.textContent = sev;

            const bar = document.createElement("div");
            bar.className = "vsp-chart-row-bar";
            const inner = document.createElement("div");
            inner.className = "vsp-chart-row-bar-inner vsp-chart-sev-" + sev.toLowerCase();
            inner.style.width = widthPercent(v, totalSev) + "%";
            bar.appendChild(inner);

            const val = document.createElement("div");
            val.className = "vsp-chart-row-value";
            val.textContent = fmt(v);

            row.appendChild(label);
            row.appendChild(bar);
            row.appendChild(val);
            sevWrap.appendChild(row);
          });

          panelSev.appendChild(sevWrap);

          // ========== Chuẩn hoá object → string cho Top CWE / Module ==========
          function normalizeTop(val, type) {
            if (val == null) return "-";
            if (typeof val === "string" || typeof val === "number" || typeof val === "boolean") {
              return String(val);
            }
            try {
              if (type === "cwe") {
                return val.code || val.cwe || val.id || val.name || JSON.stringify(val);
              }
              if (type === "module") {
                const path = val.file || val.path || val.module || val.package || val.name;
                if (!path) return JSON.stringify(val);
                try {
                  const parts = String(path).split("/").filter(Boolean);
                  return parts[parts.length - 1] || path;
                } catch (e) {
                  return path;
                }
              }
            } catch (e) {
              return "[object]";
            }
          }

          const topTool  = dash.top_risky_tool || "-";
          const topCwe   = normalizeTop(dash.top_impacted_cwe, "cwe");
          const topMod   = normalizeTop(dash.top_vulnerable_module, "module");
          const latestId = dash.latest_run_id || "-";

          // ========== Chart 2: Top risk indicators ==========
          const panelTop = document.createElement("div");
          panelTop.className = "vsp-panel";
          panelTop.innerHTML =
            '<div class="vsp-panel-title">Top risk indicators</div>' +
            '<div class="vsp-top-meta">' +
            '  <div>' +
            '    <div class="vsp-top-label">Top risky tool</div>' +
            '    <div class="vsp-top-value">' + topTool + '</div>' +
            '  </div>' +
            '  <div>' +
            '    <div class="vsp-top-label">Top CWE</div>' +
            '    <div class="vsp-top-value">' + topCwe + '</div>' +
            '  </div>' +
            '  <div>' +
            '    <div class="vsp-top-label">Top vulnerable module</div>' +
            '    <div class="vsp-top-value">' + topMod + '</div>' +
            '  </div>' +
            '  <div>' +
            '    <div class="vsp-top-label">Latest FULL_EXT run</div>' +
            '    <div class="vsp-top-value">' + latestId + '</div>' +
            '  </div>' +
            '</div>';

          // ========== Build topN by tool / CWE từ datasource ==========
          const byTool = {};
          const byCwe  = {};

          items.forEach(it => {
            try {
              const tool = it.tool || it.tool_name || "unknown";
              const cweRaw = it.cwe || it.cwe_id || it.cwe_code || it.cwe_name;
              const cwe = cweRaw || "N/A";
              byTool[tool] = (byTool[tool] || 0) + 1;
              byCwe[cwe]   = (byCwe[cwe]   || 0) + 1;
            } catch (e) {}
          });

          function topN(obj, n) {
            return Object.entries(obj)
              .sort((a, b) => b[1] - a[1])
              .slice(0, n);
          }

          const topTools = topN(byTool, 5);
          const topCwes  = topN(byCwe, 5);

          function buildBarPanel(title, entries, extraClass) {
            const panel = document.createElement("div");
            panel.className = "vsp-panel";
            panel.innerHTML = '<div class="vsp-panel-title">' + title + '</div>';

            const wrap = document.createElement("div");
            wrap.className = "vsp-chart-rows";

            let max = 0;
            entries.forEach(([k, v]) => { if (v > max) max = v; });

            function w(v) {
              if (!max) return 0;
              return Math.max(8, (v / max) * 100);
            }

            entries.forEach(([k, v]) => {
              const row = document.createElement("div");
              row.className = "vsp-chart-row";

              const label = document.createElement("div");
              label.className = "vsp-chart-row-label";
              label.textContent = k;

              const bar = document.createElement("div");
              bar.className = "vsp-chart-row-bar";
              const inner = document.createElement("div");
              inner.className = "vsp-chart-row-bar-inner " + (extraClass || "");
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

          // ========== Chart 3: Findings by tool ==========
          let panelTool = null;
          if (topTools.length) {
            panelTool = buildBarPanel("Findings by tool", topTools, "vsp-chart-sev-high");
          }

          // ========== Chart 4: Top CWE exposure ==========
          let panelCwe = null;
          if (topCwes.length) {
            panelCwe = buildBarPanel("Top CWE exposure", topCwes, "vsp-chart-sev-medium");
          }

          // Gắn đúng 4 panel vào grid
          chartsRoot.appendChild(panelSev);
          chartsRoot.appendChild(panelTop);
          if (panelTool) chartsRoot.appendChild(panelTool);
          if (panelCwe) chartsRoot.appendChild(panelCwe);

          console.log(LOG, "Rendered 4 charts (sev/top/tool/cwe).");
        } catch (e) {
          console.warn(LOG, "Error", e);
        }
      }

      if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", loadCharts);
      } else {
        loadCharts();
      }
    })();
  </script>
"""

txt = txt[:idx] + snippet + "\\n" + txt[idx:]
tpl_path.write_text(txt, encoding="utf-8")
print("[PATCH] Đã inject VSP_DASH_CHARTS_V4.")
PY
