#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$ROOT/templates/vsp_dashboard_2025.html"
BACKUP="$TPL.bak_charts_simple_$(date +%Y%m%d_%H%M%S)"

echo "[BACKUP] $TPL -> $BACKUP"
cp "$TPL" "$BACKUP"

python - << 'PY'
import pathlib

tpl_path = pathlib.Path("templates/vsp_dashboard_2025.html")
txt = tpl_path.read_text(encoding="utf-8")

if "VSP_DASH_CHARTS_SIMPLE_V1" in txt:
    print("[PATCH] Charts simple đã tồn tại – skip.")
    raise SystemExit(0)

marker = "</body>"
idx = txt.rfind(marker)
if idx == -1:
    raise SystemExit("[ERR] Không tìm thấy </body> trong template.")

snippet = """
  <script>
    // [VSP_DASH_CHARTS_SIMPLE_V1] Vẽ 2 panel Chart zone từ /api/vsp/dashboard_v3
    (async function () {
      const LOG = "[VSP_DASH_CHARTS_SIMPLE_V1]";
      try {
        const res = await fetch("/api/vsp/dashboard_v3");
        if (!res.ok) {
          console.warn(LOG, "HTTP", res.status);
          return;
        }
        const data = await res.json();
        const by = (data && data.by_severity) || {};
        const order = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];

        function fmt(v) {
          const n = Number(v);
          if (Number.isFinite(n)) return n.toLocaleString();
          return String(v ?? "0");
        }

        const root = document.getElementById("vsp-dashboard-charts-root");
        if (!root) {
          console.warn(LOG, "Không thấy #vsp-dashboard-charts-root");
          return;
        }
        // Xoá mọi thứ cũ (nếu có) để đảm bảo layout sạch
        root.innerHTML = "";

        // ==== Panel trái: Severity distribution ====
        var total = 0;
        order.forEach(function(sev) { total += Number(by[sev] || 0); });
        function widthPercent(v) {
          if (!total) return 0;
          return Math.max(4, (v / total) * 100);
        }

        const left = document.createElement("div");
        left.className = "vsp-panel";
        left.innerHTML = '<div class="vsp-panel-title">Severity distribution</div>';

        const rowsWrap = document.createElement("div");
        rowsWrap.className = "vsp-chart-rows";

        order.forEach(function(sev) {
          const v = Number(by[sev] || 0);
          const row = document.createElement("div");
          row.className = "vsp-chart-row";

          const label = document.createElement("div");
          label.className = "vsp-chart-row-label";
          label.textContent = sev;

          const bar = document.createElement("div");
          bar.className = "vsp-chart-row-bar";
          const inner = document.createElement("div");
          inner.className = "vsp-chart-row-bar-inner vsp-chart-sev-" + sev.toLowerCase();
          inner.style.width = widthPercent(v) + "%";
          bar.appendChild(inner);

          const val = document.createElement("div");
          val.className = "vsp-chart-row-value";
          val.textContent = fmt(v);

          row.appendChild(label);
          row.appendChild(bar);
          row.appendChild(val);
          rowsWrap.appendChild(row);
        });

        left.appendChild(rowsWrap);

        // ==== Panel phải: Top risk indicators ====
        const right = document.createElement("div");
        right.className = "vsp-panel";
        right.innerHTML =
          '<div class="vsp-panel-title">Top risk indicators</div>' +
          '<div class="vsp-top-meta">' +
          '  <div>' +
          '    <div class="vsp-top-label">Top risky tool</div>' +
          '    <div class="vsp-top-value">' + (data.top_risky_tool || "-") + "</div>" +
          "  </div>" +
          '  <div>' +
          '    <div class="vsp-top-label">Top CWE</div>' +
          '    <div class="vsp-top-value">' + (data.top_impacted_cwe && (data.top_impacted_cwe.code || data.top_impacted_cwe.cwe || data.top_impacted_cwe.id || data.top_impacted_cwe) || "-") + "</div>" +
          "  </div>" +
          '  <div>' +
          '    <div class="vsp-top-label">Top vulnerable module</div>' +
          '    <div class="vsp-top-value">' + (data.top_vulnerable_module && (data.top_vulnerable_module.name || data.top_vulnerable_module.module || data.top_vulnerable_module.package || data.top_vulnerable_module.file || data.top_vulnerable_module.path || data.top_vulnerable_module) || "-") + "</div>" +
          "  </div>" +
          '  <div>' +
          '    <div class="vsp-top-label">Latest FULL_EXT run</div>' +
          '    <div class="vsp-top-value">' + (data.latest_run_id || "-") + "</div>" +
          "  </div>" +
          "</div>";

        // Gắn 2 panel vào grid
        root.appendChild(left);
        root.appendChild(right);
      } catch (e) {
        console.warn(LOG, "Error", e);
      }
    })();
  </script>
"""

txt = txt[:idx] + snippet + "\\n" + txt[idx:]
tpl_path.write_text(txt, encoding="utf-8")
print("[PATCH] Đã inject VSP_DASH_CHARTS_SIMPLE_V1.")
PY
