#!/usr/bin/env bash
set -euo pipefail

echo "[PATCH_DS_CHARTS] Bắt đầu patch vsp_datasource_charts_v1.js để vẽ biểu đồ..."

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
JS_FILE="$UI_ROOT/static/js/vsp_datasource_charts_v1.js"

if [ ! -f "$JS_FILE" ]; then
  echo "[PATCH_DS_CHARTS][ERR] Không tìm thấy JS: $JS_FILE"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="${JS_FILE}.bak_bar_${TS}"
cp "$JS_FILE" "$BACKUP"
echo "[PATCH_DS_CHARTS] Backup: $JS_FILE -> $BACKUP"

export JS_FILE

python - << 'PY'
import os, pathlib, sys

js_path = pathlib.Path(os.environ["JS_FILE"])
txt = js_path.read_text(encoding="utf-8")

marker = "VSP_DS_CHARTS_BAR_V1"
if marker in txt:
    print("[PATCH_DS_CHARTS] Đã có snippet BAR_V1, bỏ qua.")
    sys.exit(0)

snippet = """

// VSP_DS_CHARTS_BAR_V1
// Vẽ 2 Chart.js: Severity by tool (stacked bar) + Top directories (horizontal bar)
// dựa trên dữ liệu /api/vsp/datasource_v2?limit=1000

(function() {
  const LOG = "[VSP_DS_CHARTS_BAR]";

  function ensureCanvas(cardTitle, canvasId) {
    const allEls = Array.from(document.querySelectorAll("*"));
    let titleEl = null;
    for (const el of allEls) {
      const text = (el.textContent || "").trim().toUpperCase();
      if (text === cardTitle.toUpperCase()) {
        titleEl = el;
        break;
      }
    }
    if (!titleEl) {
      console.warn(LOG, "Không tìm thấy card title:", cardTitle);
      return null;
    }
    let card = titleEl.closest(".vsp-chart-card");
    if (!card) {
      card = titleEl.closest("div");
    }
    if (!card) {
      console.warn(LOG, "Không tìm thấy card container cho:", cardTitle);
      return null;
    }

    let wrapper = card.querySelector(".vsp-chart-canvas-wrapper");
    if (!wrapper) {
      const body = card.querySelector(".vsp-chart-card-body") || card;
      wrapper = document.createElement("div");
      wrapper.className = "vsp-chart-canvas-wrapper";
      body.appendChild(wrapper);
    }

    let canvas = wrapper.querySelector("canvas#" + canvasId);
    if (!canvas) {
      canvas = document.createElement("canvas");
      canvas.id = canvasId;
      wrapper.innerHTML = "";
      wrapper.appendChild(canvas);
    }
    return canvas;
  }

  async function loadData() {
    const res = await fetch("/api/vsp/datasource_v2?limit=1000");
    const data = await res.json();
    return data.items || [];
  }

  function aggregate(items) {
    const severityOrder = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
    const byTool = {};
    const byDir = {};

    for (const f of items) {
      const tool = (f.tool || "unknown").toString();
      const sevRaw = (f.severity || "UNKNOWN").toString().toUpperCase();
      const sev = severityOrder.includes(sevRaw) ? sevRaw : "INFO";

      if (!byTool[tool]) {
        byTool[tool] = {};
        for (const s of severityOrder) byTool[tool][s] = 0;
      }
      byTool[tool][sev] += 1;

      const path = f.path || "";
      if (path) {
        const parts = path.split("/");
        const dir = parts.slice(0, 3).join("/") + (parts.length > 3 ? "/..." : "");
        byDir[dir] = (byDir[dir] || 0) + 1;
      }
    }

    const tools = Object.keys(byTool).sort((a,b) => {
      const sa = Object.values(byTool[a]).reduce((x,y)=>x+y,0);
      const sb = Object.values(byTool[b]).reduce((x,y)=>x+y,0);
      return sb - sa;
    }).slice(0, 6); // tối đa 6 tool

    const dirs = Object.entries(byDir).sort((a,b)=>b[1]-a[1]).slice(0, 6);

    return { severityOrder, tools, byTool, dirs };
  }

  function buildSeverityChart(ctx, agg) {
    const { severityOrder, tools, byTool } = agg;
    if (!tools.length) {
      console.log(LOG, "Không có data để vẽ chart severity-by-tool.");
      return;
    }
    const colors = {
      CRITICAL: "#ef4444",
      HIGH: "#f97316",
      MEDIUM: "#eab308",
      LOW: "#22c55e",
      INFO: "#0ea5e9",
      TRACE: "#64748b"
    };

    const datasets = severityOrder.map((sev) => ({
      label: sev,
      data: tools.map(t => byTool[t][sev] || 0),
      backgroundColor: colors[sev] || "#6b7280",
      stack: "severity"
    }));

    new Chart(ctx, {
      type: "bar",
      data: {
        labels: tools,
        datasets
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: "bottom",
            labels: { color: "#e5e7eb", font: { size: 10 } }
          },
          tooltip: {
            mode: "index",
            intersect: false
          }
        },
        scales: {
          x: {
            stacked: true,
            ticks: { color: "#9ca3af", font: { size: 10 } },
            grid: { display: false }
          },
          y: {
            stacked: true,
            ticks: { color: "#9ca3af", font: { size: 10 } },
            grid: { color: "rgba(148,163,184,0.25)" }
          }
        }
      }
    });
  }

  function buildDirsChart(ctx, agg) {
    const { dirs } = agg;
    if (!dirs.length) {
      console.log(LOG, "Không có data để vẽ chart top-directories.");
      return;
    }

    const labels = dirs.map(([dir]) => dir);
    const values = dirs.map(([,count]) => count);

    new Chart(ctx, {
      type: "bar",
      data: {
        labels,
        datasets: [{
          label: "Findings",
          data: values,
          backgroundColor: "#38bdf8"
        }]
      },
      options: {
        indexAxis: "y",
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: { mode: "nearest", intersect: true }
        },
        scales: {
          x: {
            ticks: { color: "#9ca3af", font: { size: 10 } },
            grid: { color: "rgba(148,163,184,0.25)" }
          },
          y: {
            ticks: { color: "#9ca3af", font: { size: 10 } },
            grid: { display: false }
          }
        }
      }
    });
  }

  async function init() {
    if (typeof Chart === "undefined") {
      console.warn(LOG, "Chart.js chưa được load (window.Chart undefined).");
      return;
    }
    try {
      const items = await loadData();
      if (!items.length) {
        console.log(LOG, "Không có findings để vẽ mini charts.");
        return;
      }
      const agg = aggregate(items);

      const canvasTool = ensureCanvas("SEVERITY BY TOOL", "vsp-ds-chart-tools");
      const canvasDir  = ensureCanvas("TOP DIRECTORIES", "vsp-ds-chart-dirs");

      if (canvasTool) {
        buildSeverityChart(canvasTool.getContext("2d"), agg);
      }
      if (canvasDir) {
        buildDirsChart(canvasDir.getContext("2d"), agg);
      }
    } catch (e) {
      console.warn(LOG, "Init error:", e);
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
"""

js_path.write_text(txt + snippet, encoding="utf-8")
print("[PATCH_DS_CHARTS] Đã append BAR snippet vào", js_path)
PY

echo "[PATCH_DS_CHARTS] Done."
