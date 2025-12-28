#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$ROOT/templates/vsp_dashboard_2025.html"
BACKUP="$TPL.bak_kpi_simple_v2_$(date +%Y%m%d_%H%M%S)"

echo "[BACKUP] $TPL -> $BACKUP"
cp "$TPL" "$BACKUP"

python - << 'PY'
import pathlib

tpl_path = pathlib.Path("templates/vsp_dashboard_2025.html")
txt = tpl_path.read_text(encoding="utf-8")

if "VSP_DASH_KPI_SIMPLE_V2" in txt:
    print("[PATCH] V2 đã có – skip.")
    raise SystemExit(0)

marker = "</body>"
idx = txt.rfind(marker)
if idx == -1:
    raise SystemExit("[ERR] Không tìm thấy </body> trong template.")

snippet = """
  <script>
    // [VSP_DASH_KPI_SIMPLE_V2] luôn render KPI + chart + snapshot
    (async function() {
      const LOG = "[VSP_DASH_KPI_SIMPLE_V2]";
      try {
        const res = await fetch("/api/vsp/dashboard_v3");
        if (!res.ok) {
          console.warn(LOG, "HTTP", res.status);
          return;
        }
        const data = await res.json();
        const by = (data && data.by_severity) || {};
        const order = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
        const labels = {
          CRITICAL: "Critical",
          HIGH: "High",
          MEDIUM: "Medium",
          LOW: "Low",
          INFO: "Info",
          TRACE: "Trace"
        };

        function fmt(v) {
          const n = Number(v);
          if (Number.isFinite(n)) return n.toLocaleString();
          return String(v ?? "0");
        }

        // --- KPI cards ---
        (function() {
          const root = document.getElementById("vsp-dashboard-kpi-root");
          if (!root) return;
          root.innerHTML = ""; // xoá comment cũ

          const pillMap = {
            CRITICAL: "critical",
            HIGH: "high",
            MEDIUM: "medium",
            LOW: "low",
            INFO: "info",
            TRACE: "trace"
          };

          order.forEach(function(sev) {
            const val = by[sev] || 0;
            const card = document.createElement("div");
            card.className = "vsp-kpi-card";
            card.innerHTML =
              '<div class="vsp-kpi-card__label">' + labels[sev] + "</div>" +
              '<div class="vsp-kpi-card__value">' + fmt(val) + "</div>" +
              '<div class="vsp-kpi-card__sub">Findings</div>' +
              '<div class="vsp-kpi-pill vsp-kpi-pill--' + pillMap[sev] + '">' + sev + "</div>";
            root.appendChild(card);
          });

          const adv = [
            { label: "Security Score", value: data.security_posture_score ?? "-", sub: "/ 100" },
            { label: "Top risky tool", value: data.top_risky_tool || "-", sub: "" },
            { label: "Top CWE", value: data.top_impacted_cwe || "-", sub: "" },
            { label: "Top vulnerable module", value: data.top_vulnerable_module || "-", sub: "" }
          ];
          adv.forEach(function(item) {
            const card = document.createElement("div");
            card.className = "vsp-kpi-card";
            card.innerHTML =
              '<div class="vsp-kpi-card__label">' + item.label + "</div>" +
              '<div class="vsp-kpi-card__value">' + (item.value ?? "-") + "</div>" +
              '<div class="vsp-kpi-card__sub">' + (item.sub || "") + "</div>";
            root.appendChild(card);
          });
        })();

        // --- Chart zone đơn giản ---
        (function() {
          const root = document.getElementById("vsp-dashboard-charts-root");
          if (!root) return;
          root.innerHTML = "";

          var max = 0;
          order.forEach(function(sev) {
            var v = by[sev] || 0;
            if (v > max) max = v;
          });
          function width(v) {
            if (!max) return 0;
            return Math.max(4, (v / max) * 100);
          }

          const left = document.createElement("div");
          left.className = "vsp-panel";
          left.innerHTML = '<div class="vsp-panel-title">Severity distribution</div>';
          const wrap = document.createElement("div");
          wrap.className = "vsp-chart-rows";

          order.forEach(function(sev) {
            const v = by[sev] || 0;
            const row = document.createElement("div");
            row.className = "vsp-chart-row";

            const label = document.createElement("div");
            label.className = "vsp-chart-row-label";
            label.textContent = sev;

            const bar = document.createElement("div");
            bar.className = "vsp-chart-row-bar";
            const inner = document.createElement("div");
            inner.className = "vsp-chart-row-bar-inner vsp-chart-sev-" + sev.toLowerCase();
            inner.style.width = width(v) + "%";
            bar.appendChild(inner);

            const val = document.createElement("div");
            val.className = "vsp-chart-row-value";
            val.textContent = fmt(v);

            row.appendChild(label);
            row.appendChild(bar);
            row.appendChild(val);
            wrap.appendChild(row);
          });

          left.appendChild(wrap);

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
            '    <div class="vsp-top-value">' + (data.top_impacted_cwe || "-") + "</div>" +
            "  </div>" +
            '  <div>' +
            '    <div class="vsp-top-label">Top vulnerable module</div>' +
            '    <div class="vsp-top-value">' + (data.top_vulnerable_module || "-") + "</div>" +
            "  </div>" +
            '  <div>' +
            '    <div class="vsp-top-label">Latest FULL_EXT run</div>' +
            '    <div class="vsp-top-value">' + (data.latest_run_id || "-") + "</div>" +
            "  </div>" +
            "</div>";

          root.appendChild(left);
          root.appendChild(right);
        })();

        // --- Findings snapshot ---
        (function() {
          const root = document.getElementById("vsp-dashboard-findings-root");
          if (!root) return;
          root.innerHTML = "";

          var total = data.total_findings;
          try {
            const n = Number(total);
            if (Number.isFinite(n)) total = n.toLocaleString();
          } catch (e) {}

          const p = document.createElement("p");
          p.style.fontSize = "12px";
          p.style.color = "var(--vsp-text-soft)";
          p.style.margin = "0";
          p.innerHTML =
            'Tổng: <strong>' + (total ?? "-") + "</strong> findings, " +
            "score <strong>" + (data.security_posture_score ?? "-") + "</strong> / 100. " +
            "Chi tiết xem trong tab <strong>Data Source</strong> và <strong>Runs &amp; Reports</strong>.";
          root.classList.add("vsp-panel");
          root.appendChild(p);
        })();

      } catch (e) {
        console.warn(LOG, "Error", e);
      }
    })();
  </script>
"""

txt = txt[:idx] + snippet + "\n" + txt[idx:]
tpl_path.write_text(txt, encoding="utf-8")
print("[PATCH] Đã inject V2 KPI + chart + snapshot.")
PY
