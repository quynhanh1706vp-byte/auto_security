/**
 * vsp_tab_datasource_v1.js
 * - Đọc /api/vsp/datasource_v2
 * - Đổ list findings vào bảng trong tab Data Source
 *
 * Cần một <tbody id="vsp-datasource-tbody"> trong HTML.
 */
(function () {
  const API_DS = "/api/vsp/datasource_v2";

  function $(id) {
    return document.getElementById(id);
  }

  function escapeHtml(str) {
    if (str === null || str === undefined) return "";
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  function sevBadgeClass(sev) {
    switch (sev) {
      case "CRITICAL": return "sev-badge sev-critical";
      case "HIGH":     return "sev-badge sev-high";
      case "MEDIUM":   return "sev-badge sev-medium";
      case "LOW":      return "sev-badge sev-low";
      case "INFO":     return "sev-badge sev-info";
      case "TRACE":    return "sev-badge sev-trace";
      default:         return "sev-badge";
    }
  }

  function renderTable(data) {
    const tbody = $("vsp-datasource-tbody");
    if (!tbody) return;

    const items = data.items || [];
    tbody.innerHTML = "";

    for (const f of items) {
      const sevEff = (f.severity_effective || f.severity || "").toUpperCase();
      const tool   = f.tool || "";
      const rule   = f.rule_id || f.rule_name || "";
      const file   = f.file || "";
      const line   = f.line || "";
      const msg    = f.message || f.title || "";

      const tr = document.createElement("tr");

      tr.innerHTML = `
        <td><span class="${sevBadgeClass(sevEff)}">${escapeHtml(sevEff)}</span></td>
        <td>${escapeHtml(tool)}</td>
        <td>${escapeHtml(rule)}</td>
        <td>${escapeHtml(file)}${line ? ":" + line : ""}</td>
        <td>${escapeHtml(msg)}</td>
      `;

      tbody.appendChild(tr);
    }
  }

  async function loadDatasource() {
    try {
      const url = API_DS + "?severity=HIGH&limit=200"; // mặc định HIGH, limit 200
      const resp = await fetch(url);
      if (!resp.ok) {
        console.error("[VSP][DS] HTTP error", resp.status);
        return;
      }
      const data = await resp.json();
      if (!data || !data.ok) {
        console.warn("[VSP][DS] payload ok=false hoặc rỗng");
        return;
      }
      renderTable(data);
      console.log("[VSP][DS] Render", data.total, "findings");
    } catch (err) {
      console.error("[VSP][DS] Lỗi fetch /api/vsp/datasource_v2:", err);
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", loadDatasource);
  } else {
    loadDatasource();
  }
})();


// ====================================================================
// [VSP][DS_CHARTS_V2] Data Insights (By severity / By tool) dùng data thật
// Nguồn: /api/vsp/datasource_v2?severity=ALL&limit=5000
// ====================================================================
(function () {
  function fetchJSON(url) {
    return fetch(url).then(function (res) {
      if (!res.ok) throw new Error("HTTP " + res.status + " for " + url);
      return res.json();
    });
  }

  function findCanvasByTitle(titleText) {
    var all = document.querySelectorAll("*");
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      if (!el || !el.textContent) continue;
      var t = el.textContent.trim();
      if (t === titleText || t.indexOf(titleText) !== -1) {
        var container = el;
        for (var up = 0; up < 3; up++) {
          if (!container) break;
          var canvas = container.querySelector("canvas");
          if (canvas) return canvas;
          container = container.parentElement;
        }
      }
    }
    return null;
  }

  function getChartInstance(ctx) {
    if (window.Chart && typeof Chart.getChart === "function") {
      return Chart.getChart(ctx);
    }
    if (window.Chart && Chart.instances) {
      for (var id in Chart.instances) {
        if (Object.prototype.hasOwnProperty.call(Chart.instances, id)) {
          var inst = Chart.instances[id];
          if (inst && inst.ctx === ctx) return inst;
        }
      }
    }
    return null;
  }

  function buildSeverityChart(canvas, bySeverity) {
    if (!window.Chart || !canvas) return;

    var ctx = canvas.getContext("2d");
    var existing = getChartInstance(ctx);
    if (existing) existing.destroy();

    var order = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "TRACE"];
    var labels = ["Critical", "High", "Medium", "Low", "Info", "Trace"];
    var data = order.map(function (k) { return Number(bySeverity[k] || 0); });

    new Chart(ctx, {
      type: "doughnut",
      data: {
        labels: labels,
        datasets: [{
          data: data,
          backgroundColor: [
            "#ff4b5c",
            "#ff9f40",
            "#ffcd56",
            "#4bc0c0",
            "#36a2eb",
            "#9ca3af"
          ]
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: "right",
            labels: { color: "#e5e7eb", boxWidth: 12 }
          }
        }
      }
    });
  }

  function buildToolChart(canvas, byTool) {
    if (!window.Chart || !canvas || !byTool) return;

    var ctx = canvas.getContext("2d");
    var existing = getChartInstance(ctx);
    if (existing) existing.destroy();

    var labels = Object.keys(byTool);
    var data = labels.map(function (k) { return Number(byTool[k] || 0); });

    new Chart(ctx, {
      type: "bar",
      data: {
        labels: labels,
        datasets: [{
          label: "Findings by tool",
          data: data
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { labels: { color: "#e5e7eb" } }
        },
        scales: {
          x: {
            ticks: { color: "#9ca3af" },
            grid:  { color: "rgba(148,163,184,0.15)" }
          },
          y: {
            beginAtZero: true,
            ticks: { color: "#9ca3af" },
            grid:  { color: "rgba(148,163,184,0.2)" }
          }
        }
      }
    });
  }

  function initDsCharts() {
    try {
      var sevCanvas  = findCanvasByTitle("By severity");
      var toolCanvas = findCanvasByTitle("By tool");

      if (!sevCanvas && !toolCanvas) {
        console.warn("[VSP][DS_CHARTS_V2] Không tìm thấy canvas Data Insights.");
        return;
      }

      fetchJSON("/api/vsp/datasource_v2?severity=ALL&limit=5000")
        .then(function (payload) {
          var items = (payload && payload.items) || [];
          var bySeverity = {};
          var byTool = {};

          items.forEach(function (it) {
            var sev  = (it.severity || "INFO").toUpperCase();
            var tool = it.tool || "Unknown";

            bySeverity[sev] = (bySeverity[sev] || 0) + 1;
            byTool[tool]    = (byTool[tool] || 0) + 1;
          });

          if (sevCanvas)  buildSeverityChart(sevCanvas, bySeverity);
          if (toolCanvas) buildToolChart(toolCanvas, byTool);

          console.log("[VSP][DS_CHARTS_V2] Render charts Data Source OK.", {
            total_items: items.length
          });
        })
        .catch(function (err) {
          console.error("[VSP][DS_CHARTS_V2] Lỗi load datasource_v2:", err);
        });
    } catch (e) {
      console.error("[VSP][DS_CHARTS_V2] Exception:", e);
    }
  }

  // Chỉ chạy khi trang đã load hẳn, delay 600ms để layout xong
  window.addEventListener("load", function () {
    setTimeout(initDsCharts, 600);
  });

  window.VSP_DS_CHARTS_V2 = { init: initDsCharts };
})();

