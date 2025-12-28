/* VSP_P2_TREND_PATH_FORCE_V2 */
(() => {
  // ======================= API ENDPOINTS =======================
  const API = {
    settings: "/api/vsp/settings/get",
    dashboard: "/api/vsp/dashboard_v3",
    trend: "/api/vsp/trend_v1?path=run_gate_summary.json",
    runsIndex: "/api/vsp/runs_index_v3",
    datasource: "/api/vsp/datasource_v2",
    overrides: "/api/vsp/overrides/list",
    topFindings: "/api/vsp/top_findings_v1?limit=20",
  };

  // ======================= STATE & CHARTS ======================
  let severityDonut = null;
  let trendChart = null;
  let dsChartSeverity = null;
  let dsChartTool = null;
  let dsChartCwe = null;
  let dsChartDir = null;

  let runsRaw = [];
  let dsRawItems = [];
  let dsPage = 1;
  const DS_PAGE_SIZE = 50;

  // ======================= UTILS ===============================
  function showToast(message, type = "info") {
    const toast = document.getElementById("vsp-toast");
    if (!toast) return;
    toast.textContent = message;
    toast.className = "vsp-toast";
    toast.classList.add("show", `vsp-toast-${type}`);
    setTimeout(() => {
      toast.classList.remove("show");
    }, 3500);
  }

  async function fetchJSON(url, opts = {}) {
    try {
      const res = await fetch(url, opts);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return await res.json();
    } catch (err) {
      console.error("[VSP][FETCH]", url, err);
      showToast(`Lỗi tải dữ liệu: ${url}`, "error");
      return null;
    }
  }

  // ======================= TABS & HEADER =======================
  function initTabs() {
    const buttons = document.querySelectorAll(".vsp-tab-btn");
    const panes = document.querySelectorAll(".vsp-tab-pane");

    buttons.forEach((btn) => {
      btn.addEventListener("click", () => {
        const tab = btn.dataset.tab;
        buttons.forEach((b) =>
          b.classList.toggle("active", b === btn)
        );
        panes.forEach((p) =>
          p.classList.toggle("active", p.id === `tab-${tab}`)
        );
      });
    });
  }

  function initRunButton() {
    const btn = document.getElementById("vsp-run-btn");
    if (!btn) return;
    btn.addEventListener("click", () => {
      showToast(
        "RUN FULL SCAN – sẽ nối với run_vsp_full_ext.sh / API trigger trong phase sau.",
        "info"
      );
    });
  }

  async function loadSettingsAndHeader() {
    const data = await fetchJSON(API.settings);
    const envChip = document.getElementById("vsp-env-chip");
    const srcChip = document.getElementById("vsp-src-chip");

    if (!data) {
      if (envChip) envChip.textContent = "PROFILE: EXT+";
      if (srcChip) srcChip.textContent = "SRC: --";
      return;
    }

    const profile =
      data.profile ||
      data.PROFILE ||
      data.profile_name ||
      "EXT+";
    const src =
      data.src_path ||
      data.source_path ||
      data.repo ||
      data.src ||
      "--";

    if (envChip) envChip.textContent = `PROFILE: ${profile}`;
    if (srcChip) srcChip.textContent = `SRC: ${src}`;

    // Tab 4 – Env grid
    const envGrid = document.getElementById("vsp-env-grid");
    if (envGrid) {
      envGrid.innerHTML = "";
      const entries = [
        ["Profile", profile],
        ["Source path", src],
        ["Last run id", data.last_run_id || data.last_run || "--"],
        ["Last run time", data.last_run_ts || data.last_run_time || "--"],
        ["Bundle out dir", data.out_dir || "--"],
      ];
      entries.forEach(([label, value]) => {
        const div = document.createElement("div");
        div.className = "vsp-env-item";
        div.innerHTML = `
          <div class="vsp-env-label">${label}</div>
          <div class="vsp-env-value">${value}</div>
        `;
        envGrid.appendChild(div);
      });
    }

    // Tab 4 – Tool stack
    const tbody = document.getElementById("vsp-tools-tbody");
    if (tbody && Array.isArray(data.tools)) {
      tbody.innerHTML = "";
      data.tools.forEach((t) => {
        const status = t.enabled === false ? "DISABLED" : "ENABLED";
        const tr = document.createElement("tr");
        tr.innerHTML = `
          <td>${t.name || ""}</td>
          <td>${t.description || ""}</td>
          <td>${status}</td>
        `;
        tbody.appendChild(tr);
      });
    }
  }

  // ======================= TAB 1 – DASHBOARD ===================
  function renderDashboardKpis(dash) {
    const by = dash.by_severity || dash.bySeverity || {};
    const get = (k) => by[k] || 0;

    const total = dash.total_findings || dash.total || 0;
    const sevCritical = get("CRITICAL");
    const sevHigh = get("HIGH");
    const sevMed = get("MEDIUM");
    const sevLow = get("LOW");
    const sevInfo = get("INFO");
    const sevTrace = get("TRACE");

    const elTotal = document.getElementById("kpi-total");
    const elCritical = document.getElementById("kpi-critical");
    const elHigh = document.getElementById("kpi-high");
    const elMedium = document.getElementById("kpi-medium");
    const elLow = document.getElementById("kpi-low");
    const elInfoTrace = document.getElementById("kpi-info-trace");

    if (elTotal) elTotal.textContent = total;
    if (elCritical) elCritical.textContent = sevCritical;
    if (elHigh) elHigh.textContent = sevHigh;
    if (elMedium) elMedium.textContent = sevMed;
    if (elLow) elLow.textContent = sevLow;
    if (elInfoTrace) elInfoTrace.textContent = sevInfo + sevTrace;

    const sub = document.getElementById("vsp-last-run-subtitle");
    const meta = document.getElementById("vsp-last-run-meta");
    if (sub) {
      sub.textContent = dash.run_id
        ? `Last run: ${dash.run_id}`
        : "No run yet.";
    }
    if (meta) {
      const score =
        dash.security_score !== undefined ? dash.security_score : dash.score;
      const tool = dash.top_risky_tool || dash.top_tool || "--";
      const cwe = dash.top_cwe || "--";
      const module = dash.top_module || "--";
      meta.innerHTML = `
        <span class="vsp-meta-chip">
          Security Score: <strong>${score ?? "--"}</strong>
        </span>
        <span class="vsp-meta-chip">
          Top tool: <strong>${tool}</strong>
        </span>
        <span class="vsp-meta-chip">
          Top CWE: <strong>${cwe}</strong>
        </span>
        <span class="vsp-meta-chip">
          Top module: <strong>${module}</strong>
        </span>
      `;
    }
  }

  function renderSeverityDonut(dash) {
    const ctx = document.getElementById("chart-severity-donut");
    if (!ctx || typeof Chart === "undefined") return;

    const raw = dash.by_severity || dash.bySeverity || {};
    const order = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "TRACE"];
    const data = order.map((k) => raw[k] || 0);

    if (severityDonut) {
      severityDonut.data.labels = order;
      severityDonut.data.datasets[0].data = data;
      severityDonut.update();
      return;
    }

    severityDonut = new Chart(ctx, {
      type: "doughnut",
      data: {
        labels: order,
        datasets: [
          {
            data,
            borderWidth: 0,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        cutout: "60%",
        plugins: {
          legend: {
            position: "bottom",
            labels: {
              boxWidth: 10,
              font: { size: 10 },
            },
          },
        },
      },
    });
  }

  function renderByToolList(dash) {
    const ul = document.getElementById("vsp-bytool-list");
    if (!ul) return;

    const byTool = dash.by_tool || dash.byTool;
    if (!byTool || typeof byTool !== "object") {
      ul.innerHTML = `<li><span>No by_tool data</span><span>--</span></li>`;
      return;
    }

    const entries = Object.entries(byTool)
      .map(([tool, cnt]) => ({ tool, cnt }))
      .sort((a, b) => b.cnt - a.cnt)
      .slice(0, 6);

    ul.innerHTML = "";
    entries.forEach((item) => {
      const li = document.createElement("li");
      li.innerHTML = `
        <span>${item.tool}</span>
        <span>${item.cnt}</span>
      `;
      ul.appendChild(li);
    });
  }

  function renderTrend(trend) {
    const ctx = document.getElementById("chart-trend");
    if (!ctx || typeof Chart === "undefined") return;
    if (!trend) return;

    const points = Array.isArray(trend.points) ? trend.points : trend;
    if (!Array.isArray(points)) return;

    const labels = points.map((p) => p.label || p.ts || p.run_id || "");
    const data = points.map((p) => p.total || p.total_findings || 0);

    if (trendChart) {
      trendChart.data.labels = labels;
      trendChart.data.datasets[0].data = data;
      trendChart.update();
      return;
    }

    trendChart = new Chart(ctx, {
      type: "line",
      data: {
        labels,
        datasets: [
          {
            label: "Total findings",
            data,
            tension: 0.25,
            fill: false,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
        },
        scales: {
          x: {
            ticks: { maxRotation: 0, font: { size: 9 } },
          },
          y: {
            beginAtZero: true,
          },
        },
      },
    });
  }

  async function loadTopFindings() {
    const data = await fetchJSON(API.topFindings);
    if (!data || !Array.isArray(data.items)) return;

    const table = document.querySelector(
      "#tab-dashboard .vsp-risk-mid-grid .vsp-risk-card:nth-child(1) table.vsp-table-compact"
    );
    if (!table) return;
    const tbody = table.querySelector("tbody");
    if (!tbody) return;

    tbody.innerHTML = "";
    data.items.slice(0, 8).forEach((f) => {
      const sev = f.severity || f.severity_effective || "INFO";
      const sevClass =
        sev === "CRITICAL"
          ? "sev-critical"
          : sev === "HIGH"
          ? "sev-high"
          : "";

      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td><span class="vsp-badge ${sevClass}">${sev}</span></td>
        <td>${f.file || f.location || ""}${
        f.line ? `:${f.line}` : ""
      }</td>
        <td>${f.cwe || f.rule_id || f.rule_name || ""}</td>
        <td>${f.tool || ""}</td>
      `;
      tbody.appendChild(tr);
    });
  }

  async function loadDashboard() {
    const dash = await fetchJSON(API.dashboard);
    if (!dash) return;

    renderDashboardKpis(dash);
    renderSeverityDonut(dash);
    renderByToolList(dash);

    const trend = await fetchJSON(API.trend);
    if (trend) {
      renderTrend(trend);
    }

    loadTopFindings().catch((e) =>
      console.warn("[VSP] top findings failed", e)
    );
  }

  // ======================= TAB 2 – RUNS & REPORTS ==============
  function ensureRunsKpiStrip() {
    const panelBody = document.querySelector(
      ".vsp-panel-runs-list .vsp-panel-body"
    );
    if (!panelBody) return null;

    let kpiStrip = panelBody.querySelector(".vsp-runs-kpi-strip");
    const table = panelBody.querySelector("table");
    if (!table) return null;

    if (!kpiStrip) {
      kpiStrip = document.createElement("div");
      kpiStrip.className = "vsp-runs-kpi-strip";
      kpiStrip.innerHTML = `
        <div class="vsp-kpi-mini">
          <div class="label">Total runs</div>
          <div class="value" id="runs-kpi-total-runs">--</div>
        </div>
        <div class="vsp-kpi-mini">
          <div class="label">Last 10: OK/Fail</div>
          <div class="value" id="runs-kpi-ok-fail">--</div>
        </div>
        <div class="vsp-kpi-mini">
          <div class="label">Avg findings/run</div>
          <div class="value" id="runs-kpi-avg">--</div>
        </div>
        <div class="vsp-kpi-mini">
          <div class="label">Tools enabled</div>
          <div class="value" id="runs-kpi-tools">--</div>
        </div>
      `;
      panelBody.insertBefore(kpiStrip, table);
    }
    return kpiStrip;
  }

  function ensureRunsFilters() {
    const panelBody = document.querySelector(
      ".vsp-panel-runs-list .vsp-panel-body"
    );
    if (!panelBody) return;

    let filterBar = panelBody.querySelector(".vsp-runs-filters");
    const table = panelBody.querySelector("table");
    if (!table) return;

    if (!filterBar) {
      filterBar = document.createElement("div");
      filterBar.className = "vsp-runs-filters";
      filterBar.innerHTML = `
        <select id="runs-filter-profile">
          <option value="">Profile: All</option>
          <option value="FAST">FAST</option>
          <option value="EXT">EXT</option>
          <option value="EXT+">EXT+</option>
          <option value="AGGR">AGGR</option>
          <option value="FULL">FULL</option>
        </select>
        <select id="runs-filter-tool">
          <option value="">Tool: All</option>
          <option value="semgrep">semgrep</option>
          <option value="gitleaks">gitleaks</option>
          <option value="bandit">bandit</option>
          <option value="kics">kics</option>
          <option value="trivy_fs">trivy_fs</option>
          <option value="grype">grype</option>
          <option value="syft">syft</option>
          <option value="codeql">codeql</option>
        </select>
        <select id="runs-filter-range">
          <option value="all">All time</option>
          <option value="7d">Last 7 days</option>
          <option value="30d">Last 30 days</option>
        </select>
        <input id="runs-filter-search" placeholder="Search run id / SRC / URL / commit..." />
        <button id="runs-filter-apply" class="vsp-btn-secondary">Apply</button>
      `;
      panelBody.insertBefore(filterBar, table);
    }

    const applyBtn = document.getElementById("runs-filter-apply");
    if (applyBtn && !applyBtn.dataset._bound) {
      applyBtn.dataset._bound = "1";
      applyBtn.addEventListener("click", renderRunsTable);
    }
  }

  function applyRunsFilter(list) {
    const profileSel = document.getElementById("runs-filter-profile");
    const toolSel = document.getElementById("runs-filter-tool");
    const rangeSel = document.getElementById("runs-filter-range");
    const searchInput = document.getElementById("runs-filter-search");

    const profile = profileSel ? profileSel.value : "";
    const tool = toolSel ? toolSel.value : "";
    const range = rangeSel ? rangeSel.value : "all";
    const q = searchInput ? searchInput.value.trim().toLowerCase() : "";

    let filtered = list.slice();

    if (profile) {
      filtered = filtered.filter((r) => {
        const p = (r.profile || r.profile_name || "").toUpperCase();
        return p.includes(profile.toUpperCase());
      });
    }

    if (tool) {
      filtered = filtered.filter((r) => {
        const byTool = r.by_tool || {};
        return Object.prototype.hasOwnProperty.call(byTool, tool);
      });
    }

    if (range !== "all") {
      const now = new Date();
      const days =
        range === "7d" ? 7 : range === "30d" ? 30 : 0;
      if (days > 0) {
        const cutoff = now.getTime() - days * 24 * 60 * 60 * 1000;
        filtered = filtered.filter((r) => {
          const tsString = r.ts || r.time || r.timestamp;
          if (!tsString) return true;
          const t = new Date(tsString).getTime();
          if (Number.isNaN(t)) return true;
          return t >= cutoff;
        });
      }
    }

    if (q) {
      filtered = filtered.filter((r) => {
        const src =
          r.src ||
          r.src_path ||
          r.source ||
          "";
        const url = r.url || r.app_url || "";
        const commit = r.commit || r.git_commit || "";
        const runId = r.run_id || "";
        const haystack = `${runId} ${src} ${url} ${commit}`.toLowerCase();
        return haystack.includes(q);
      });
    }

    return filtered;
  }

  function renderRunsKpis() {
    ensureRunsKpiStrip();
    const totalRuns = runsRaw.length;
    const last10 = runsRaw.slice(0, 10);
    const ok = last10.filter(
      (r) => r.status === "OK" || r.ok === true
    ).length;
    const fail = last10.length - ok;

    const avg =
      totalRuns === 0
        ? 0
        : Math.round(
            runsRaw.reduce(
              (s, r) => s + (r.total_findings || r.total || 0),
              0
            ) / totalRuns
          );

    const toolsSet = new Set();
    runsRaw.forEach((r) => {
      const byTool = r.by_tool || {};
      Object.keys(byTool).forEach((t) => toolsSet.add(t));
    });

    const elTotal = document.getElementById("runs-kpi-total-runs");
    const elOkFail = document.getElementById("runs-kpi-ok-fail");
    const elAvg = document.getElementById("runs-kpi-avg");
    const elTools = document.getElementById("runs-kpi-tools");

    if (elTotal) elTotal.textContent = totalRuns;
    if (elOkFail) elOkFail.textContent = `${ok}/${fail}`;
    if (elAvg) elAvg.textContent = avg;
    if (elTools) elTools.textContent = toolsSet.size;
  }

  function renderRunDetail(run) {
    const subtitle = document.getElementById("vsp-run-detail-subtitle");
    const link = document.getElementById("vsp-run-report-link");
    const container = document.getElementById("vsp-run-detail-content");

    if (subtitle) {
      subtitle.textContent = `Run: ${
        run.run_id
      } – ${run.ts || run.time || ""}`;
    }

    if (link) {
      if (run.report_html) {
        link.href = run.report_html;
        link.classList.remove("vsp-link-hidden");
      } else {
        link.href = "#";
        link.classList.add("vsp-link-hidden");
      }
    }

    if (!container) return;
    container.innerHTML = "";

    const by = run.by_severity || run.bySeverity || {};
    const byTool = run.by_tool || run.byTool || {};

    const severityCard = document.createElement("div");
    severityCard.className = "vsp-run-detail-card";
    severityCard.innerHTML = `
      <h4>By severity</h4>
      <ul class="vsp-run-detail-list">
        <li>CRITICAL: ${by.CRITICAL || 0}</li>
        <li>HIGH: ${by.HIGH || 0}</li>
        <li>MEDIUM: ${by.MEDIUM || 0}</li>
        <li>LOW: ${by.LOW || 0}</li>
        <li>INFO: ${by.INFO || 0}</li>
        <li>TRACE: ${by.TRACE || 0}</li>
      </ul>
    `;
    container.appendChild(severityCard);

    const toolCard = document.createElement("div");
    toolCard.className = "vsp-run-detail-card";
    const toolList = Object.entries(byTool)
      .map(([tool, cnt]) => `<li>${tool}: ${cnt}</li>`)
      .join("");
    toolCard.innerHTML = `
      <h4>By tool</h4>
      <ul class="vsp-run-detail-list">
        ${toolList || "<li>No by_tool data</li>"}
      </ul>
    `;
    container.appendChild(toolCard);
  }

  function renderRunsTable() {
    const tbody = document.getElementById("vsp-runs-tbody");
    if (!tbody) return;
    tbody.innerHTML = "";

    const filtered = applyRunsFilter(runsRaw);

    filtered.forEach((run) => {
      const by = run.by_severity || run.bySeverity || {};
      const byTool = run.by_tool || run.byTool || {};
      const tools = Object.keys(byTool).join(", ");

      const profile =
        run.profile || run.profile_name || "--";
      const src =
        run.src || run.src_path || run.source || "--";
      const url = run.url || run.app_url || "--";

      const tr = document.createElement("tr");
      tr.dataset.runId = run.run_id;
      tr.innerHTML = `
        <td>${run.run_id}</td>
        <td>${run.ts || run.time || ""}</td>
        <td>${profile}</td>
        <td>${src}</td>
        <td>${url}</td>
        <td>${by.CRITICAL || 0}</td>
        <td>${by.HIGH || 0}</td>
        <td>${by.MEDIUM || 0}</td>
        <td>${by.LOW || 0}</td>
        <td>${by.INFO || 0}</td>
        <td>${by.TRACE || 0}</td>
        <td>${run.total_findings || run.total || 0}</td>
        <td>${tools}</td>
        <td>${
          run.report_html
            ? `<a href="${run.report_html}" target="_blank">HTML</a>`
            : "-"
        }</td>
      `;
      tr.addEventListener("click", () => renderRunDetail(run));
      tbody.appendChild(tr);
    });
  }

  async function loadRuns() {
    const data = await fetchJSON(API.runsIndex);
    runsRaw = Array.isArray(data) ? data : [];
    ensureRunsKpiStrip();
    ensureRunsFilters();
    renderRunsKpis();
    renderRunsTable();
  }

  // ======================= TAB 3 – DATA SOURCE =================
  function getDsFilters() {
    const toolSel = document.getElementById("ds-tool");
    const sevSel = document.getElementById("ds-severity");
    const searchInput = document.getElementById("ds-search");
    const cweInput = document.getElementById("ds-cwe");
    const folderInput = document.getElementById("ds-folder");

    return {
      tool: toolSel ? toolSel.value : "",
      severity: sevSel ? sevSel.value : "",
      q: searchInput ? searchInput.value.trim() : "",
      cwe: cweInput ? cweInput.value.trim() : "",
      folder: folderInput ? folderInput.value.trim() : "",
    };
  }

  function filterDsItems() {
    const { tool, severity, q, cwe, folder } = getDsFilters();

    let filtered = dsRawItems.slice();

    if (tool) {
      filtered = filtered.filter((it) => it.tool === tool);
    }
    if (severity) {
      filtered = filtered.filter(
        (it) =>
          it.severity === severity ||
          it.severity_effective === severity
      );
    }
    if (q) {
      const lower = q.toLowerCase();
      filtered = filtered.filter((it) => {
        const msg =
          it.message || it.description || "";
        const file = it.file || "";
        const rule =
          it.rule_id || it.rule_name || "";
        const combined = `${msg} ${file} ${rule}`.toLowerCase();
        return combined.includes(lower);
      });
    }
    if (cwe) {
      const lower = cwe.toLowerCase();
      filtered = filtered.filter((it) =>
        (it.cwe || "").toLowerCase().includes(lower)
      );
    }
    if (folder) {
      const lower = folder.toLowerCase();
      filtered = filtered.filter((it) =>
        (it.file || "").toLowerCase().includes(lower)
      );
    }

    return filtered;
  }

  function renderDatasourceTable() {
    const tbody = document.getElementById("vsp-ds-tbody");
    const totalEl = document.getElementById("vsp-ds-total");
    const pageLabel = document.getElementById("ds-page-label");
    if (!tbody) return;

    const filtered = filterDsItems();
    const total = filtered.length;
    const pageCount = Math.max(
      1,
      Math.ceil(total / DS_PAGE_SIZE)
    );
    if (dsPage > pageCount) dsPage = pageCount;

    const start = (dsPage - 1) * DS_PAGE_SIZE;
    const end = start + DS_PAGE_SIZE;
    const pageItems = filtered.slice(start, end);

    tbody.innerHTML = "";
    pageItems.forEach((it, idx) => {
      const sev =
        it.severity || it.severity_effective || "INFO";
      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td>${start + idx + 1}</td>
        <td>${it.tool || ""}</td>
        <td>${sev}</td>
        <td>${it.file || ""}</td>
        <td>${it.line || ""}</td>
        <td>${it.rule_id || it.rule_name || ""}</td>
        <td>${it.message || it.description || ""}</td>
      `;
      tbody.appendChild(tr);
    });

    if (totalEl) {
      totalEl.textContent = `Total: ${total}`;
    }
    if (pageLabel) {
      pageLabel.textContent = `Page ${dsPage} / ${pageCount}`;
    }

    renderDatasourceCharts();
  }

  function renderDatasourceCharts() {
    if (typeof Chart === "undefined") return;
    if (!Array.isArray(dsRawItems) || dsRawItems.length === 0) return;

    const filtered = filterDsItems();

    const sevCounts = {
      CRITICAL: 0,
      HIGH: 0,
      MEDIUM: 0,
      LOW: 0,
      INFO: 0,
      TRACE: 0,
    };
    const toolCounts = {};
    const cweCounts = {};
    const dirCounts = {};

    filtered.forEach((it) => {
      const sev =
        it.severity || it.severity_effective || "INFO";
      if (sevCounts[sev] !== undefined) {
        sevCounts[sev] += 1;
      }

      const tool = it.tool || "unknown";
      toolCounts[tool] = (toolCounts[tool] || 0) + 1;

      const cwe = it.cwe;
      if (cwe) {
        cweCounts[cwe] = (cweCounts[cwe] || 0) + 1;
      }

      const file = it.file || "";
      if (file) {
        const parts = file.split("/");
        const dir =
          parts.length > 2
            ? `${parts[0]}/${parts[1]}`
            : parts[0] || "";
        if (dir) {
          dirCounts[dir] = (dirCounts[dir] || 0) + 1;
        }
      }
    });

    // Các chart bên Tab 3 chỉ vẽ nếu có canvas tương ứng trong HTML
    const ctxSev = document.getElementById("ds-chart-sev");
    if (ctxSev) {
      const labels = Object.keys(sevCounts);
      const data = labels.map((k) => sevCounts[k]);
      if (!dsChartSeverity) {
        dsChartSeverity = new Chart(ctxSev, {
          type: "doughnut",
          data: { labels, datasets: [{ data, borderWidth: 0 }] },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            cutout: "60%",
            plugins: { legend: { display: false } },
          },
        });
      } else {
        dsChartSeverity.data.labels = labels;
        dsChartSeverity.data.datasets[0].data = data;
        dsChartSeverity.update();
      }
    }

    const ctxTool = document.getElementById("ds-chart-tool");
    if (ctxTool) {
      const entries = Object.entries(toolCounts)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 8);
      const labels = entries.map((e) => e[0]);
      const data = entries.map((e) => e[1]);
      if (!dsChartTool) {
        dsChartTool = new Chart(ctxTool, {
          type: "bar",
          data: { labels, datasets: [{ data }] },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: { legend: { display: false } },
          },
        });
      } else {
        dsChartTool.data.labels = labels;
        dsChartTool.data.datasets[0].data = data;
        dsChartTool.update();
      }
    }

    const ctxCwe = document.getElementById("ds-chart-cwe");
    if (ctxCwe) {
      const entries = Object.entries(cweCounts)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 5);
      const labels = entries.map((e) => e[0]);
      const data = entries.map((e) => e[1]);
      if (!dsChartCwe) {
        dsChartCwe = new Chart(ctxCwe, {
          type: "bar",
          data: { labels, datasets: [{ data }] },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: { legend: { display: false } },
          },
        });
      } else {
        dsChartCwe.data.labels = labels;
        dsChartCwe.data.datasets[0].data = data;
        dsChartCwe.update();
      }
    }

    const ctxDir = document.getElementById("ds-chart-dir");
    if (ctxDir) {
      const entries = Object.entries(dirCounts)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 5);
      const labels = entries.map((e) => e[0]);
      const data = entries.map((e) => e[1]);
      if (!dsChartDir) {
        dsChartDir = new Chart(ctxDir, {
          type: "bar",
          data: { labels, datasets: [{ data }] },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: { legend: { display: false } },
          },
        });
      } else {
        dsChartDir.data.labels = labels;
        dsChartDir.data.datasets[0].data = data;
        dsChartDir.update();
      }
    }
  }

  async function loadDatasourceRaw() {
    const data = await fetchJSON(`${API.datasource}?limit=10000`);
    if (!data || !Array.isArray(data.items)) {
      dsRawItems = [];
      return;
    }
    dsRawItems = data.items;
    dsPage = 1;
    renderDatasourceTable();
  }

  function initDatasourceEvents() {
    const applyBtn = document.getElementById("ds-apply");
    const prevBtn = document.getElementById("ds-prev");
    const nextBtn = document.getElementById("ds-next");

    if (applyBtn && !applyBtn.dataset._bound) {
      applyBtn.dataset._bound = "1";
      applyBtn.addEventListener("click", () => {
        dsPage = 1;
        renderDatasourceTable();
      });
    }
    if (prevBtn && !prevBtn.dataset._bound) {
      prevBtn.dataset._bound = "1";
      prevBtn.addEventListener("click", () => {
        if (dsPage > 1) {
          dsPage -= 1;
          renderDatasourceTable();
        }
      });
    }
    if (nextBtn && !nextBtn.dataset._bound) {
      nextBtn.dataset._bound = "1";
      nextBtn.addEventListener("click", () => {
        const filtered = filterDsItems();
        const pageCount = Math.max(
          1,
          Math.ceil(filtered.length / DS_PAGE_SIZE)
        );
        if (dsPage < pageCount) {
          dsPage += 1;
          renderDatasourceTable();
        }
      });
    }
  }

  // ======================= TAB 5 – OVERRIDES ===================
  async function loadOverrides() {
    const res = await fetchJSON(API.overrides);
    const tbody = document.querySelector(
      "#tab-overrides table.vsp-table-compact tbody"
    );
    if (!tbody || !res || !Array.isArray(res.items)) return;

    const items = res.items;
    tbody.innerHTML = "";
    items.forEach((ov) => {
      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td>${ov.tool || ""}</td>
        <td>${ov.rule_id || ""}</td>
        <td>${ov.scope || ""}</td>
        <td>${ov.action || ov.override || ""}</td>
        <td>${ov.note || ov.reason || ""}</td>
      `;
      tr.addEventListener("mouseenter", () => {
        showToast(
          "Impact preview (demo) – phase sau sẽ highlight findings bị ảnh hưởng.",
          "info"
        );
      });
      tbody.appendChild(tr);
    });

    const metricsContainer = document.getElementById("vsp-overrides-metrics");
    if (metricsContainer) {
      const total = items.length;
      const critDown = items.filter((ov) => {
        const from = (ov.from || ov.current || "").toUpperCase();
        const to = (ov.to || ov.override || "").toUpperCase();
        return from === "CRITICAL" && to && to !== "CRITICAL";
      }).length;
      metricsContainer.textContent = `Overrides: ${total}, Critical downgraded: ${critDown}`;
    }
  }

  // ======================= INIT ================================
  async function init() {
    initTabs();
    initRunButton();
    initDatasourceEvents();

    await loadSettingsAndHeader();
    await loadDashboard();
    await loadRuns();
    await loadDatasourceRaw();
    loadOverrides().catch((e) =>
      console.warn("[VSP] overrides error", e)
    );
  }

  document.addEventListener("DOMContentLoaded", init);
})();
