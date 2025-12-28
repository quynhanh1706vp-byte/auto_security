#!/usr/bin/env bash
set -euo pipefail

HTML="$PWD/SECURITY_BUNDLE_FULL_5_PAGES.html"

echo "[i] HTML = $HTML"

if [ ! -f "$HTML" ]; then
  echo "[ERR] Không tìm thấy file HTML: $HTML" >&2
  exit 1
fi

backup="$HTML.bak_$(date +%Y%m%d_%H%M%S)"
cp "$HTML" "$backup"
echo "[i] Đã backup: $backup"

python3 - "$HTML" <<'PY'
from pathlib import Path
import sys

html_path = Path(sys.argv[1])
text = html_path.read_text(encoding="utf-8")

marker = "</body>"

if "MODERN_CHARTS_PATCH_V2" in text:
    print("[i] MODERN_CHARTS_PATCH_V2 đã tồn tại, bỏ qua.")
    raise SystemExit(0)

insert = r"""
  <!-- MODERN_CHARTS_PATCH_V2: improved dashboard charts -->
  <style>
    .modern-chart-card {
      background: radial-gradient(circle at top left, #1a273a, #050812);
      border-radius: 18px;
      padding: 18px 20px 20px;
      box-shadow: 0 14px 40px rgba(0, 0, 0, 0.55);
      border: 1px solid rgba(255, 255, 255, 0.02);
    }

    .modern-chart-card-header {
      display: flex;
      justify-content: space-between;
      align-items: baseline;
      margin-bottom: 10px;
    }

    .modern-chart-card-title {
      font-size: 12px;
      letter-spacing: 0.16em;
      text-transform: uppercase;
      color: rgba(255, 255, 255, 0.72);
    }

    .modern-chart-card-subtitle {
      font-size: 11px;
      color: rgba(255, 255, 255, 0.45);
    }

    .modern-chart-card-body {
      position: relative;
      height: 230px;
    }

    .modern-chart-card-body canvas {
      width: 100% !important;
      height: 100% !important;
    }

    .chartjs-tooltip {
      background: rgba(7, 15, 32, 0.95);
      color: #ffffff;
      border-radius: 10px;
      padding: 8px 10px;
      font-size: 11px;
      box-shadow: 0 12px 30px rgba(0, 0, 0, 0.65);
    }
  </style>

  <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>

  <script>
    const severityCounts = {
      C: 0,
      H: 170,
      M: 8891,
      L: 10,
      I: 0,
      T: 0
    };

    const trendLabels = ["-9", "-8", "-7", "-6", "-5", "-4", "-3", "-2", "-1", "Last"];
    const trendValues = [2400, 2300, 2600, 2800, 3000, 3400, 3600, 3800, 4100, 4300];

    const severityColors = {
      C: "#ff4b5c",
      H: "#ff9f1a",
      M: "#ffd93d",
      L: "#2bcbba",
      I: "#8e9aac",
      T: "#6b7a8f"
    };

    function findCardByTitle(keyword) {
      const blocks = document.querySelectorAll("section, div, article");
      const kw = keyword.toLowerCase();
      for (const el of blocks) {
        const txt = el.textContent || "";
        if (txt.toLowerCase().includes(kw)) {
          return el;
        }
      }
      return null;
    }

    function rebuildCard(cardEl, titleText, subtitleText, canvasId) {
      if (!cardEl) return null;

      cardEl.classList.add("modern-chart-card");

      while (cardEl.firstChild) cardEl.removeChild(cardEl.firstChild);

      const header = document.createElement("div");
      header.className = "modern-chart-card-header";

      const title = document.createElement("span");
      title.className = "modern-chart-card-title";
      title.textContent = titleText;

      const subtitle = document.createElement("span");
      subtitle.className = "modern-chart-card-subtitle";
      subtitle.textContent = subtitleText;

      header.appendChild(title);
      header.appendChild(subtitle);

      const body = document.createElement("div");
      body.className = "modern-chart-card-body";

      const canvas = document.createElement("canvas");
      canvas.id = canvasId;
      body.appendChild(canvas);

      cardEl.appendChild(header);
      cardEl.appendChild(body);

      return canvas;
    }

    function initSeverityChart(canvasId) {
      const canvas = document.getElementById(canvasId);
      if (!canvas || !window.Chart) return;
      const ctx = canvas.getContext("2d");

      const labels = Object.keys(severityCounts);
      const data = labels.map(k => severityCounts[k]);
      const colors = labels.map(k => severityColors[k]);

      new Chart(ctx, {
        type: "bar",
        data: {
          labels: labels,
          datasets: [{
            label: "Findings",
            data: data,
            backgroundColor: colors,
            borderRadius: 12,
            borderWidth: 0,
            maxBarThickness: 38
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          layout: { padding: { top: 8, right: 12, bottom: 0, left: 4 } },
          plugins: {
            legend: { display: false },
            tooltip: {
              backgroundColor: "rgba(7, 15, 32, 0.95)",
              titleColor: "#fff",
              bodyColor: "#fff",
              borderColor: "rgba(255,255,255,0.08)",
              borderWidth: 1,
              padding: 10,
              displayColors: false,
              callbacks: {
                title: (ctx) => {
                  const map = {C: "CRITICAL", H: "HIGH", M: "MEDIUM", L: "LOW", I: "INFO", T: "TRACE"};
                  return map[ctx[0].label] || ctx[0].label;
                },
                label: (ctx) => "Findings: " + ctx.parsed.y
              }
            }
          },
          scales: {
            x: {
              grid: { display: false },
              ticks: {
                color: "rgba(255,255,255,0.7)",
                font: { size: 11 }
              }
            },
            y: {
              grid: {
                color: "rgba(255,255,255,0.06)",
                drawBorder: false
              },
              ticks: {
                color: "rgba(255,255,255,0.4)",
                font: { size: 10 },
                beginAtZero: true
              }
            }
          }
        }
      });
    }

    function initTrendChart(canvasId) {
      const canvas = document.getElementById(canvasId);
      if (!canvas || !window.Chart) return;
      const ctx = canvas.getContext("2d");

      const gradient = ctx.createLinearGradient(0, 0, 0, ctx.canvas.height);
      gradient.addColorStop(0, "rgba(46, 213, 115, 0.55)");
      gradient.addColorStop(1, "rgba(46, 213, 115, 0.02)");

      new Chart(ctx, {
        type: "line",
        data: {
          labels: trendLabels,
          datasets: [{
            label: "Total findings",
            data: trendValues,
            fill: true,
            backgroundColor: gradient,
            borderColor: "#2ed573",
            borderWidth: 2,
            tension: 0.35,
            pointRadius: 3.5,
            pointHoverRadius: 5,
            pointBackgroundColor: "#2ed573",
            pointBorderWidth: 0
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          layout: { padding: { top: 8, right: 12, bottom: 0, left: 4 } },
          plugins: {
            legend: { display: false },
            tooltip: {
              backgroundColor: "rgba(7, 15, 32, 0.95)",
              titleColor: "#fff",
              bodyColor: "#fff",
              borderColor: "rgba(255,255,255,0.08)",
              borderWidth: 1,
              padding: 10,
              callbacks: {
                title: (ctx) => "Run " + ctx[0].label,
                label: (ctx) => "Findings: " + ctx.parsed.y
              }
            }
          },
          scales: {
            x: {
              grid: { display: false },
              ticks: {
                color: "rgba(255,255,255,0.6)",
                font: { size: 10 }
              }
            },
            y: {
              grid: {
                color: "rgba(255,255,255,0.07)",
                drawBorder: false
              },
              ticks: {
                color: "rgba(255,255,255,0.4)",
                font: { size: 10 },
                beginAtZero: true
              }
            }
          }
        }
      });
    }

    function initModernCharts() {
      const sevCard = findCardByTitle("SEVERITY BUCKETS");
      const trendCard =
        findCardByTitle("TREND - LAST RUNS") ||
        findCardByTitle("TREND – LAST RUNS") ||
        findCardByTitle("TREND");

      const sevCanvas = rebuildCard(
        sevCard,
        "SEVERITY BUCKETS – LAST RUN",
        "Interactive overview",
        "severityChart"
      );

      const trendCanvas = rebuildCard(
        trendCard,
        "TREND – LAST RUNS",
        "Total findings over time",
        "trendChart"
      );

      if (sevCanvas) initSeverityChart(sevCanvas.id);
      if (trendCanvas) initTrendChart(trendCanvas.id);
    }

    document.addEventListener("DOMContentLoaded", function () {
      if (typeof Chart === "undefined") {
        console.warn("[SECURITY_BUNDLE] Chart.js chưa load.");
        return;
      }
      try {
        initModernCharts();
      } catch (e) {
        console.error("[SECURITY_BUNDLE] Lỗi initModernCharts:", e);
      }
    });
  </script>
"""

if marker not in text:
    raise SystemExit("[ERR] Không tìm thấy </body> trong HTML, không patch được.")

text = text.replace(marker, insert + "\n</body>")
html_path.write_text(text, encoding="utf-8")
print("[i] Đã chèn MODERN_CHARTS_PATCH_V2 vào HTML.")
PY

echo "[i] Done."
