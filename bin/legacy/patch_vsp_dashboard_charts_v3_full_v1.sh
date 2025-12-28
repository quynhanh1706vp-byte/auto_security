#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/js/vsp_dashboard_charts_pretty_v3.js"
LOG="[VSP_CHARTS_V3_PATCH]"

if [ -f "$JS" ]; then
  BAK="$JS.bak_full_v3_$(date +%Y%m%d_%H%M%S)"
  cp "$JS" "$BAK"
  echo "$LOG Backup $JS -> $BAK"
fi

cat > "$JS" << 'JS'
/**
 * VSP 2025 – Dashboard charts pretty v3 (FULL)
 *
 * Được gọi từ vsp_dashboard_enhance_v1.js:
 *   window.VSP_CHARTS_V3.updateFromDashboard(dashboard_v3_json)
 *
 * Vẽ 4 chart:
 *   1) Severity donut
 *   2) Findings trend (line)
 *   3) Critical / High by tool (stacked bar)
 *   4) Top CWE exposure (horizontal bar)
 *
 * Layout assumption:
 *   #vsp-dashboard-main chứa 4 ".vsp-chart-card" theo đúng thứ tự:
 *     [0] Severity Distribution
 *     [1] Findings Trend
 *     [2] Critical / High by tool
 *     [3] Top CWE exposure
 *
 * Nếu trong card đang có text placeholder như
 *   "donut chart: 6 severity buckets"
 *   "line chart: total findings per run"
 * thì script sẽ xoá text & gắn <canvas> tương ứng.
 */

(function () {
  console.log("[VSP_CHARTS_V3] pretty charts loaded (FULL v3)");

  var charts = {};

  function ensureCanvas(index, id) {
    var cards = document.querySelectorAll("#vsp-dashboard-main .vsp-chart-card");
    if (!cards.length || index >= cards.length) {
      console.warn("[VSP_CHARTS_V3] Không tìm thấy chart card index", index);
      return null;
    }
    var card = cards[index];

    // Xoá placeholder text nếu có
    if (card.childNodes.length === 1 &&
        card.firstChild.nodeType === Node.TEXT_NODE) {
      card.textContent = "";
    }

    var canvas = card.querySelector("canvas");
    if (!canvas) {
      canvas = document.createElement("canvas");
      canvas.id = id;
      canvas.style.width = "100%";
      canvas.style.height = "100%";
      card.innerHTML = "";
      card.appendChild(canvas);
    }
    return canvas.getContext("2d");
  }

  function destroyIfExists(key) {
    if (charts[key]) {
      charts[key].destroy();
      charts[key] = null;
    }
  }

  function buildSeverityDonut(data) {
    if (typeof Chart === "undefined") {
      console.warn("[VSP_CHARTS_V3] Chart.js chưa sẵn sàng, bỏ qua severity donut.");
      return;
    }
    var ctx = ensureCanvas(0, "vsp-chart-severity");
    if (!ctx) return;

    var sev = data.by_severity || {};
    var labels = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "TRACE"];
    var colors = [
      "#f97373", // CRITICAL – đỏ
      "#fb923c", // HIGH – cam
      "#facc15", // MEDIUM – vàng
      "#22c55e", // LOW – xanh lá
      "#38bdf8", // INFO – xanh dương
      "#a855f7"  // TRACE – tím
    ];
    var values = labels.map(function (k) { return sev[k] || 0; });

    destroyIfExists("severity");

    charts.severity = new Chart(ctx, {
      type: "doughnut",
      data: {
        labels: labels,
        datasets: [{
          data: values,
          backgroundColor: colors,
          borderWidth: 0
        }]
      },
      options: {
        plugins: {
          legend: {
            position: "bottom",
            labels: { boxWidth: 10, font: { size: 11 } }
          },
          tooltip: {
            callbacks: {
              label: function (ctx) {
                var lbl = ctx.label || "";
                var v = ctx.parsed || 0;
                return lbl + ": " + v;
              }
            }
          }
        },
        cutout: "55%",
        maintainAspectRatio: false
      }
    });
  }

  function buildTrendLine(data) {
    if (typeof Chart === "undefined") {
      console.warn("[VSP_CHARTS_V3] Chart.js chưa sẵn sàng, bỏ qua trend.");
      return;
    }
    var ctx = ensureCanvas(1, "vsp-chart-trend");
    if (!ctx) return;

    var trend = data.trend_by_run || [];
    if (!Array.isArray(trend) || !trend.length) {
      console.warn("[VSP_CHARTS_V3] Không có trend_by_run.");
      return;
    }

    // sort theo thời gian tăng dần
    trend.sort(function (a, b) {
      var ta = new Date(a.started_at || a.created_at || 0).getTime();
      var tb = new Date(b.started_at || b.created_at || 0).getTime();
      return ta - tb;
    });

    var labels = trend.map(function (r) {
      return (r.run_id || "").replace("RUN_", "").slice(0, 16);
    });

    var values = trend.map(function (r) {
      return r.total_findings || r.total || 0;
    });

    destroyIfExists("trend");

    charts.trend = new Chart(ctx, {
      type: "line",
      data: {
        labels: labels,
        datasets: [{
          label: "Total findings",
          data: values,
          fill: true,
          borderColor: "rgba(56,189,248,1)",      // cyan
          backgroundColor: "rgba(56,189,248,0.18)",
          tension: 0.3,
          pointRadius: 2,
          pointHoverRadius: 4
        }]
      },
      options: {
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              title: function (ctx) {
                var idx = ctx[0].dataIndex;
                return trend[idx].run_id || "";
              },
              label: function (ctx) {
                var idx = ctx.dataIndex;
                var r = trend[idx];
                var t = r.total_findings || r.total || 0;
                var when = r.started_at || r.created_at || "";
                return "Findings: " + t + " (" + when + ")";
              }
            }
          }
        },
        maintainAspectRatio: false,
        scales: {
          x: { ticks: { maxRotation: 60, minRotation: 30 } },
          y: { beginAtZero: true }
        }
      }
    });
  }

  function buildByToolBar(data) {
    if (typeof Chart === "undefined") {
      console.warn("[VSP_CHARTS_V3] Chart.js chưa sẵn sàng, bỏ qua by_tool.");
      return;
    }
    var ctx = ensureCanvas(2, "vsp-chart-bytool");
    if (!ctx) return;

    var byTool = data.by_tool || [];
    if (!Array.isArray(byTool) || !byTool.length) {
      console.warn("[VSP_CHARTS_V3] Không có by_tool.");
      return;
    }

    // Tính CRITICAL + HIGH mỗi tool, lấy top 6
    byTool.forEach(function (t) {
      var sev = t.by_severity || {};
      t._crit = sev.CRITICAL || 0;
      t._high = sev.HIGH || 0;
      t._score = t._crit * 2 + t._high;
    });

    byTool.sort(function (a, b) { return b._score - a._score; });
    var top = byTool.slice(0, 6);

    var labels = top.map(function (t) { return t.tool || t.name || ""; });
    var dataCrit = top.map(function (t) { return t._crit; });
    var dataHigh = top.map(function (t) { return t._high; });

    destroyIfExists("bytool");

    charts.bytool = new Chart(ctx, {
      type: "bar",
      data: {
        labels: labels,
        datasets: [
          {
            label: "CRITICAL",
            data: dataCrit,
            backgroundColor: "#f97373"
          },
          {
            label: "HIGH",
            data: dataHigh,
            backgroundColor: "#fb923c"
          }
        ]
      },
      options: {
        plugins: {
          legend: {
            position: "bottom",
            labels: { boxWidth: 10, font: { size: 11 } }
          }
        },
        maintainAspectRatio: false,
        responsive: true,
        scales: {
          x: { stacked: true, ticks: { autoSkip: false } },
          y: { stacked: true, beginAtZero: true }
        }
      }
    });
  }

  function buildTopCweBar(data) {
    if (typeof Chart === "undefined") {
      console.warn("[VSP_CHARTS_V3] Chart.js chưa sẵn sàng, bỏ qua top CWE.");
      return;
    }
    var ctx = ensureCanvas(3, "vsp-chart-cwe");
    if (!ctx) return;

    var list = data.top_cwe_list || [];
    if (!Array.isArray(list) || !list.length) {
      console.warn("[VSP_CHARTS_V3] Không có top_cwe_list.");
      return;
    }

    var top = list.slice(0, 8);
    var labels = top.map(function (c) { return c.cwe_id || c.cwe || ""; });
    var vals   = top.map(function (c) { return c.total_findings || c.count || 0; });

    destroyIfExists("cwe");

    charts.cwe = new Chart(ctx, {
      type: "bar",
      data: {
        labels: labels,
        datasets: [{
          data: vals,
          backgroundColor: "rgba(148,163,184,0.9)"
        }]
      },
      options: {
        indexAxis: "y",
        plugins: {
          legend: { display: false }
        },
        maintainAspectRatio: false,
        scales: {
          x: { beginAtZero: true }
        }
      }
    });
  }

  function updateFromDashboard(data) {
    if (!data || typeof data !== "object") {
      console.warn("[VSP_CHARTS_V3] updateFromDashboard – data invalid.");
      return;
    }
    buildSeverityDonut(data);
    buildTrendLine(data);
    buildByToolBar(data);
    buildTopCweBar(data);
  }

  // Public API
  window.VSP_CHARTS_V3 = {
    updateFromDashboard: updateFromDashboard
  };
})();
JS

echo "$LOG [OK] Wrote $JS"
echo "$LOG Done – pretty charts FULL v3."
