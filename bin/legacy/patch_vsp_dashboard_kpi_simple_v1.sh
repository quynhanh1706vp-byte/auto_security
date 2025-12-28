#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$ROOT/templates/vsp_dashboard_2025.html"
BACKUP="$TPL.bak_kpi_simple_$(date +%Y%m%d_%H%M%S)"

echo "[BACKUP] $TPL -> $BACKUP"
cp "$TPL" "$BACKUP"

python - << 'PY'
import pathlib

tpl_path = pathlib.Path("templates/vsp_dashboard_2025.html")
txt = tpl_path.read_text(encoding="utf-8")

if "VSP_DASH_KPI_SIMPLE_V1" in txt:
    print("[PATCH] KPI simple đã có – skip.")
    raise SystemExit(0)

# 1) Thêm CSS cho KPI card + chart hàng ngang
css_snippet = """
    /* [VSP_DASH_KPI_CARDS_CSS_V1] KPI cards + simple chart */
    .vsp-kpi-card {
      border-radius: 14px;
      padding: 10px 12px;
      background: rgba(15, 23, 42, 0.96);
      border: 1px solid rgba(148, 163, 184, 0.35);
      display: flex;
      flex-direction: column;
      gap: 4px;
      box-shadow: 0 12px 30px rgba(15, 23, 42, 0.8);
    }
    .vsp-kpi-card__label {
      font-size: 11px;
      color: var(--vsp-text-muted);
      text-transform: uppercase;
      letter-spacing: 0.05em;
    }
    .vsp-kpi-card__value {
      font-size: 18px;
      font-weight: 600;
    }
    .vsp-kpi-card__sub {
      font-size: 11px;
      color: var(--vsp-text-soft);
    }
    .vsp-kpi-pill {
      align-self: flex-start;
      padding: 2px 8px;
      border-radius: 999px;
      font-size: 10px;
      margin-top: 2px;
    }
    .vsp-kpi-pill--critical { background: rgba(239, 68, 68, 0.18); color: #fee2e2; }
    .vsp-kpi-pill--high     { background: rgba(249, 115, 22, 0.18); color: #ffedd5; }
    .vsp-kpi-pill--medium   { background: rgba(250, 204, 21, 0.18); color: #fef3c7; }
    .vsp-kpi-pill--low      { background: rgba(34, 197, 94, 0.18); color: #bbf7d0; }
    .vsp-kpi-pill--info     { background: rgba(56, 189, 248, 0.18); color: #e0f2fe; }
    .vsp-kpi-pill--trace    { background: rgba(168, 85, 247, 0.18); color: #ede9fe; }

    .vsp-chart-rows {
      margin-top: 6px;
      display: flex;
      flex-direction: column;
      gap: 6px;
    }
    .vsp-chart-row {
      display: flex;
      align-items: center;
      gap: 6px;
      font-size: 11px;
    }
    .vsp-chart-row-label {
      width: 64px;
      color: var(--vsp-text-soft);
    }
    .vsp-chart-row-bar {
      flex: 1;
      height: 6px;
      border-radius: 999px;
      background: rgba(15, 23, 42, 0.9);
      overflow: hidden;
    }
    .vsp-chart-row-bar-inner {
      height: 100%;
      border-radius: 999px;
    }
    .vsp-chart-row-value {
      width: 70px;
      text-align: right;
    }
    .vsp-chart-sev-critical { background: var(--vsp-sev-critical); }
    .vsp-chart-sev-high     { background: var(--vsp-sev-high); }
    .vsp-chart-sev-medium   { background: var(--vsp-sev-medium); }
    .vsp-chart-sev-low      { background: var(--vsp-sev-low); }
    .vsp-chart-sev-info     { background: var(--vsp-sev-info); }
    .vsp-chart-sev-trace    { background: var(--vsp-sev-trace); }

    .vsp-top-meta {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 8px;
      margin-top: 6px;
      font-size: 12px;
    }
    .vsp-top-label {
      font-size: 11px;
      color: var(--vsp-text-soft);
    }
    .vsp-top-value {
      font-size: 13px;
      font-weight: 500;
    }
"""

style_idx = txt.find("</style>")
if style_idx == -1:
    raise SystemExit("[ERR] Không tìm thấy </style> trong template.")

txt = txt[:style_idx] + css_snippet + txt[style_idx:]

# 2) Thêm script render KPI + chart + summary
js_snippet = """
  <script>
    // [VSP_DASH_KPI_SIMPLE_V1] Render KPI + chart từ /api/vsp/dashboard_v3
    (async function() {
      const LOG = "[VSP_DASH_KPI_SIMPLE_V1]";
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

        // --- KPI cards ---
        const kRoot = document.getElementById("vsp-dashboard-kpi-root");
        if (kRoot && !kRoot.hasChildNodes()) {
          const pillMap = {
            CRITICAL: "critical",
            HIGH: "high",
            MEDIUM: "medium",
            LOW: "low",
            INFO: "info",
            TRACE: "trace"
          };

          function fmt(v) {
            const n = Number(v);
            if (Number.isFinite(n)) return n.toLocaleString();
            return String(v ?? "0");
          }

          order.forEach(function(sev) {
            const val = by[sev] || 0;
            const card = document.createElement("div");
            card.className = "vsp-kpi-card";
            card.innerHTML =
              '<div class="vsp-kpi-card__label">' + labels[sev] + "</div>" +
              '<div class="vsp-kpi-card__value">' + fmt(val) + "</div>" +
              '<div class="vsp-kpi-card__sub">Findings</div>' +
              '<div class="vsp-kpi-pill vsp-kpi-pill--' + pillMap[sev] + '">' + sev + "</div>";
            kRoot.appendChild(card);
          });

          // KPI nâng cao
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
            kRoot.appendChild(card);
          });
        }

        // --- Chart zone ---
        const cRoot = document.getElementById("vsp-dashboard-charts-root");
        if (cRoot && !cRoot.hasChildNodes()) {
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
            const n = Number(v);
            val.textContent = Number.isFinite(n) ? n.toLocaleString() : String(v);

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

          cRoot.appendChild(left);
          cRoot.appendChild(right);
        }

        // --- Findings snapshot ---
        const fRoot = document.getElementById("vsp-dashboard-findings-root");
        if (fRoot && !fRoot.hasChildNodes()) {
          var total = data.total_findings;
          try {
            const n = Number(total);
            if (Number.isFinite(n)) total = n.toLocaleString();
          } catch (e) {}
          fRoot.innerHTML =
            '<div class="vsp-panel-title">Snapshot</div>' +
            '<p style="font-size:12px;color:var(--vsp-text-soft);margin:4px 0 0;">' +
            'Tổng: <strong>' + (total ?? "-") + "</strong> findings, " +
            "score <strong>" + (data.security_posture_score ?? "-") + "</strong> / 100. " +
            "Chi tiết xem trong tab <strong>Data Source</strong> và <strong>Runs &amp; Reports</strong>." +
            "</p>";
        }
      } catch (e) {
        console.warn(LOG, "Error", e);
      }
    })();
  </script>
"""

body_idx = txt.rfind("</body>")
if body_idx == -1:
    raise SystemExit("[ERR] Không tìm thấy </body> trong template.")

txt = txt[:body_idx] + js_snippet + "\n" + txt[body_idx:]
tpl_path.write_text(txt, encoding="utf-8")
print("[PATCH] Đã inject KPI + chart + snapshot.")
PY
