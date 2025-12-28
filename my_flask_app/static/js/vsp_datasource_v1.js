window.VSP_DATASOURCE = (function () {
  let initialized = false;
  let chartSeverity = null;
  let chartTool = null;

  function $(sel) {
    return document.querySelector(sel);
  }

  function $all(sel) {
    return Array.from(document.querySelectorAll(sel));
  }

  async function init() {
    if (initialized) return;
    initialized = true;

    const btnRefresh = $("#vsp-ds-refresh");
    const selSeverity = $("#vsp-ds-severity");
    const selTool = $("#vsp-ds-tool");
    const selLimit = $("#vsp-ds-limit");
    const inputSearch = $("#vsp-ds-search-input");

    if (btnRefresh) btnRefresh.addEventListener("click", refresh);
    if (selSeverity) selSeverity.addEventListener("change", refresh);
    if (selTool) selTool.addEventListener("change", refresh);
    if (selLimit) selLimit.addEventListener("change", refresh);
    if (inputSearch) {
      inputSearch.addEventListener("keydown", (e) => {
        if (e.key === "Enter") refresh();
      });
    }

    await Promise.all([loadStats(), refresh()]);
  }

  async function loadStats() {
    try {
      const data = await VSP.fetchJson("/api/vsp/datasource_stats_v1");
      if (!data || data.ok === false) {
        throw new Error("stats API error");
      }

      buildSeverityChart(data.by_severity || {});
      buildToolChart(data.by_tool || []);

      // Fill tool dropdown
      const selTool = $("#vsp-ds-tool");
      if (selTool) {
        const current = selTool.value;
        const tools = (data.by_tool || []).map(x => x.tool).filter(Boolean);
        const options = ['<option value="">All tools</option>'].concat(
          tools.map(t => `<option value="${escapeHtml(t)}">${escapeHtml(t)}</option>`)
        );
        selTool.innerHTML = options.join("");
        if (current) {
          selTool.value = current;
        }
      }
    } catch (e) {
      console.error("[VSP_DATASOURCE] stats error:", e);
      VSP.showError("Không tải được thống kê Data Source. Kiểm tra /api/vsp/datasource_stats_v1.");
    }
  }

  async function refresh() {
    try {
      VSP.clearError();
      const severity = ($("#vsp-ds-severity") || {}).value || "ALL";
      const tool = ($("#vsp-ds-tool") || {}).value || "";
      const limit = ($("#vsp-ds-limit") || {}).value || "50";
      const search = ($("#vsp-ds-search-input") || {}).value || "";

      const params = new URLSearchParams();
      params.set("severity", severity);
      params.set("limit", limit);
      if (tool) params.set("tool", tool);
      if (search) params.set("search", search);

      const url = "/api/vsp/datasource_v2?" + params.toString();
      const data = await VSP.fetchJson(url);
      if (!data || data.ok === false) {
        throw new Error("datasource API error");
      }
      renderTable(data.items || []);
    } catch (e) {
      console.error("[VSP_DATASOURCE] refresh error:", e);
      VSP.showError("Không tải được Unified Findings. Kiểm tra /api/vsp/datasource_v2.");
    }
  }

  function buildSeverityChart(bySev) {
    const ctx = document.getElementById("vsp-ds-chart-severity");
    if (!ctx || !window.Chart) return;

    if (chartSeverity) {
      chartSeverity.destroy();
      chartSeverity = null;
    }

    const order = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "TRACE"];
    const labels = order;
    const data = order.map(s => bySev[s] ?? 0);
    const colors = {
      CRITICAL: "#ff1744",
      HIGH: "#ff6d00",
      MEDIUM: "#fbbf24",
      LOW: "#22c55e",
      INFO: "#38bdf8",
      TRACE: "#a855f7"
    };

    chartSeverity = new Chart(ctx.getContext("2d"), {
      type: "bar",
      data: {
        labels,
        datasets: [
          {
            label: "Findings",
            data,
            backgroundColor: order.map(s => colors[s]),
            borderWidth: 0
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          x: {
            ticks: { color: "#9ca3af", font: { size: 10 } },
            grid: { display: false }
          },
          y: {
            ticks: { color: "#9ca3af", font: { size: 10 } },
            grid: { color: "rgba(55, 65, 81, 0.6)" }
          }
        },
        plugins: {
          legend: { display: false }
        }
      }
    });
  }

  function buildToolChart(byTool) {
    const ctx = document.getElementById("vsp-ds-chart-tool");
    if (!ctx || !window.Chart) return;

    if (chartTool) {
      chartTool.destroy();
      chartTool = null;
    }

    const labels = (byTool || []).map(x => x.tool || "N/A");
    const data = (byTool || []).map(x => x.total ?? 0);

    chartTool = new Chart(ctx.getContext("2d"), {
      type: "bar",
      data: {
        labels,
        datasets: [
          {
            label: "Total findings",
            data,
            backgroundColor: "#38bdf8",
            borderWidth: 0
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          x: {
            ticks: { color: "#9ca3af", font: { size: 10 } },
            grid: { display: false }
          },
          y: {
            ticks: { color: "#9ca3af", font: { size: 10 } },
            grid: { color: "rgba(55, 65, 81, 0.6)" }
          }
        },
        plugins: {
          legend: { display: false }
        }
      }
    });
  }

  function renderTable(items) {
    const tbody = $("#vsp-table-datasource tbody");
    if (!tbody) return;

    if (!items.length) {
      tbody.innerHTML = `<tr><td colspan="5">Không có findings phù hợp filter hiện tại.</td></tr>`;
      return;
    }

    const rows = items.map(it => {
      const sev = it.severity || "N/A";
      const tool = it.tool || "N/A";
      const ruleId = it.rule_id || it.cwe || "";
      const ruleName = it.rule_name || "";
      const loc = it.location || it.path || "";
      const msg = it.message || "";

      return `
        <tr>
          <td>${VSP.renderSeverityBadge(sev)}</td>
          <td><span class="vsp-tool-tag">${escapeHtml(tool)}</span></td>
          <td>
            <div class="vsp-rule">${escapeHtml(ruleId || "N/A")}</div>
            ${ruleName ? `<div class="vsp-rule-sub">${escapeHtml(ruleName)}</div>` : ""}
          </td>
          <td><div class="vsp-loc">${escapeHtml(loc)}</div></td>
          <td>${escapeHtml(msg)}</td>
        </tr>`;
    });

    tbody.innerHTML = rows.join("");
  }

  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  return {
    init,
    refresh
  };
})();
