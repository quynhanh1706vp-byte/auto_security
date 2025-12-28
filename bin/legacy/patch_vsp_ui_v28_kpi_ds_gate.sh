#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/js/vsp_ui_extras_v25.js"
LOG_PREFIX="[VSP_V28]"

echo "$LOG_PREFIX ROOT = $ROOT"

if [ -f "$JS" ]; then
  BAK="$JS.bak_v27_$(date +%Y%m%d_%H%M%S)"
  cp "$JS" "$BAK"
  echo "$LOG_PREFIX [BACKUP] $JS -> $BAK"
fi

cat > "$JS" << 'JS'
/**
 * VSP 2025 – UI Extras V2.8
 *  - Shell + header 5 tab
 *  - Dashboard extras (Top risks + Delta)
 *  - Global floating card: CI Gate – Latest Run (mọi tab đều thấy)
 *  - Runs & Reports:
 *      + CI/CD Gate summary dạng KPI cards
 *      + Filter Run ID / Status
 *      + Badge màu ở cột cuối
 *  - Data Source:
 *      + Summary card + mini chart (nếu Chart.js có sẵn)
 *      + Filter severity / tool
 *  - Settings:
 *      + Summary + 3 block Scan / Tools / CI Gate
 *  - Rule Overrides:
 *      + Summary bảng overrides hoặc card “không có overrides”
 */

(function () {
  console.log("[VSP_V28] vsp_ui_extras_v25.js loaded (V2.8)");

  /* ------------ HELPERS ------------ */

  function safeParseJSON(text) {
    try {
      return JSON.parse(text);
    } catch (e) {
      return null;
    }
  }

  function observeOnce(rootId, onReady) {
    var root = document.getElementById(rootId);
    if (!root) return;

    try { onReady(root); } catch (e) { console.warn("[VSP_V28] onReady initial error", e); }

    var obs = new MutationObserver(function () {
      try { onReady(root); } catch (e) { console.warn("[VSP_V28] onReady mutation error", e); }
    });
    obs.observe(root, { childList: true, subtree: true });
  }

  /* ------------ COMMON SHELL ------------ */

  function wrapShellAndHeaders() {
    [
      { id: "vsp-dashboard-main",  title: "Dashboard",       sub: "CIO-level security posture & trends" },
      { id: "vsp-runs-main",       title: "Runs & Reports",  sub: "Lịch sử quét, CI/CD Gates & export báo cáo" },
      { id: "vsp-datasource-main", title: "Data Source",     sub: "Chi tiết unified findings & mini analytics" },
      { id: "vsp-settings-main",   title: "Settings",        sub: "Scan paths, tool stack & gate policy" },
      { id: "vsp-rules-main",      title: "Rule Overrides",  sub: "Override rule severity / scope" }
    ].forEach(function (cfg) {
      var el = document.getElementById(cfg.id);
      if (!el) return;

      if (!el.classList.contains("vsp-main-shell")) {
        el.classList.add("vsp-main-shell");
      }

      if (!el.querySelector(".vsp-tab-header")) {
        var header = document.createElement("div");
        header.className = "vsp-tab-header vsp-fadein vsp-fadein-delay-1";

        var hTitle = document.createElement("div");
        hTitle.className = "vsp-tab-header-title";
        hTitle.textContent = cfg.title;

        var hSub = document.createElement("div");
        hSub.className = "vsp-tab-header-sub";
        hSub.textContent = cfg.sub;

        header.appendChild(hTitle);
        header.appendChild(hSub);

        if (el.firstChild) el.insertBefore(header, el.firstChild);
        else el.appendChild(header);
      }
    });
  }

  /* ------------ DASHBOARD EXTRAS (Top risks + Delta) ------------ */

  function animateDashboardKpis() {
    var root = document.getElementById("vsp-dashboard-main");
    if (!root) return;
    var kpis = root.querySelectorAll(".vsp-kpi-card, .vsp-chart-card");
    kpis.forEach(function (card, idx) {
      if (!card.classList.contains("vsp-fadein")) {
        card.classList.add("vsp-fadein");
        card.classList.add("vsp-fadein-delay-" + ((idx % 6) + 1));
      }
    });
  }

  function buildDashboardExtras() {
    var root = document.getElementById("vsp-dashboard-main");
    if (!root) return;

    if (!root.querySelector(".vsp-dashboard-extras-grid")) {
      var extras = document.createElement("div");
      extras.className = "vsp-dashboard-extras-grid vsp-fadein vsp-fadein-delay-2";

      // Top 10 High/Critical
      var cardTop = document.createElement("div");
      cardTop.className = "vsp-table-card";
      var headerTop = document.createElement("div");
      headerTop.className = "vsp-table-card-header";
      var hTitle = document.createElement("div");
      hTitle.className = "vsp-table-card-title";
      hTitle.textContent = "Top 10 High / Critical Findings";
      var hSub = document.createElement("div");
      hSub.className = "vsp-table-card-sub";
      hSub.textContent = "Ưu tiên CRITICAL, đọc từ /api/vsp/datasource_v2.";
      headerTop.appendChild(hTitle); headerTop.appendChild(hSub);
      cardTop.appendChild(headerTop);
      var tableTop = document.createElement("table");
      tableTop.className = "vsp-table-compact";
      tableTop.innerHTML =
        "<thead><tr><th>#</th><th>Severity</th><th>Tool</th><th>Rule</th><th>CWE</th><th>File</th><th>Line</th></tr></thead>" +
        "<tbody id='vsp-dash-top-risks-body'><tr><td colspan='7'>Đang tải...</td></tr></tbody>";
      cardTop.appendChild(tableTop);

      // Delta
      var cardDelta = document.createElement("div");
      cardDelta.className = "vsp-table-card";
      var headerDelta = document.createElement("div");
      headerDelta.className = "vsp-table-card-header";
      var dTitle = document.createElement("div");
      dTitle.className = "vsp-table-card-title";
      dTitle.textContent = "What changed since last run?";
      var dSub = document.createElement("div");
      dSub.className = "vsp-table-card-sub";
      dSub.textContent = "So sánh 2 lần quét gần nhất (Total findings & xu hướng).";
      headerDelta.appendChild(dTitle); headerDelta.appendChild(dSub);
      cardDelta.appendChild(headerDelta);
      var tableDelta = document.createElement("table");
      tableDelta.className = "vsp-table-compact";
      tableDelta.innerHTML =
        "<thead><tr><th></th><th>Run ID</th><th>Total Findings</th><th>Time / Trend</th></tr></thead>" +
        "<tbody id='vsp-dash-delta-body'><tr><td colspan='4'>Đang tải...</td></tr></tbody>";
      cardDelta.appendChild(tableDelta);

      extras.appendChild(cardTop);
      extras.appendChild(cardDelta);
      root.appendChild(extras);

      fetchTopRisks();
      fetchDeltaRuns();
    }
  }

  function fetchTopRisks() {
    var tbody = document.getElementById("vsp-dash-top-risks-body");
    if (!tbody) return;

    fetch("/api/vsp/datasource_v2?limit=1000")
      .then(function (r) { return r.json(); })
      .then(function (data) {
        var items = data.items || [];
        var shortlist = items.filter(function (it) {
          return it.severity === "CRITICAL" || it.severity === "HIGH";
        });

        shortlist.sort(function (a, b) {
          var sA = a.severity === "CRITICAL" ? 2 : 1;
          var sB = b.severity === "CRITICAL" ? 2 : 1;
          if (sA !== sB) return sB - sA;
          return 0;
        });

        shortlist = shortlist.slice(0, 10);
        if (!shortlist.length) {
          tbody.innerHTML = "<tr><td colspan='7'>Không có High/Critical trong 1000 findings đầu.</td></tr>";
          return;
        }

        tbody.innerHTML = "";
        shortlist.forEach(function (it, idx) {
          var tr = document.createElement("tr");
          tr.innerHTML =
            "<td>" + (idx + 1) + "</td>" +
            "<td>" + (it.severity || "") + "</td>" +
            "<td>" + (it.tool || "") + "</td>" +
            "<td>" + (it.rule_id || it.rule || "") + "</td>" +
            "<td>" + (it.cwe || "") + "</td>" +
            "<td>" + (it.file || "").split("/").slice(-2).join("/") + "</td>" +
            "<td>" + (it.line || "") + "</td>";
          tbody.appendChild(tr);
        });
      })
      .catch(function () {
        tbody.innerHTML = "<tr><td colspan='7'>Lỗi tải dữ liệu.</td></tr>";
      });
  }

  function fetchDeltaRuns() {
    var tbody = document.getElementById("vsp-dash-delta-body");
    if (!tbody) return;

    fetch("/api/vsp/dashboard_v3")
      .then(function (r) { return r.json(); })
      .then(function (data) {
        var trend = data.trend_by_run || [];
        if (!Array.isArray(trend) || trend.length < 2) {
          tbody.innerHTML = "<tr><td colspan='4'>Chưa đủ dữ liệu trend (cần ≥ 2 run).</td></tr>";
          return;
        }

        trend.sort(function (a, b) {
          var ta = new Date(a.started_at || a.created_at || "").getTime();
          var tb = new Date(b.started_at || b.created_at || "").getTime();
          return tb - ta;
        });

        var latest = trend[0];
        var prev = trend[1];

        var totalLatest = latest.total_findings || latest.total || 0;
        var totalPrev = prev.total_findings || prev.total || 0;
        var delta = totalLatest - totalPrev;

        var badge = document.createElement("span");
        badge.className = "vsp-badge " +
          (delta > 0 ? "vsp-badge-red" : delta < 0 ? "vsp-badge-green" : "vsp-badge-amber");
        badge.textContent =
          delta > 0 ? ("▲ +" + delta) :
          delta < 0 ? ("▼ " + delta) :
          "No change";

        tbody.innerHTML = "";

        function row(label, obj, total) {
          var tr = document.createElement("tr");
          tr.innerHTML =
            "<td>" + label + "</td>" +
            "<td>" + (obj.run_id || "") + "</td>" +
            "<td>" + total + "</td>" +
            "<td>" + (obj.started_at || obj.created_at || "") + "</td>";
          return tr;
        }

        tbody.appendChild(row("Latest", latest, totalLatest));
        tbody.appendChild(row("Previous", prev, totalPrev));

        var trDelta = document.createElement("tr");
        trDelta.innerHTML =
          "<td>Delta</td><td></td><td>" + (delta >= 0 ? "+" : "") + delta + "</td><td></td>";
        trDelta.lastChild.appendChild(badge);
        tbody.appendChild(trDelta);
      })
      .catch(function () {
        tbody.innerHTML = "<tr><td colspan='4'>Lỗi tải dữ liệu.</td></tr>";
      });
  }

  /* ------------ GLOBAL CI GATE – floating card (mọi tab) ------------ */

  function createGlobalCiGateCard() {
    if (document.getElementById("vsp-ci-gate-global-card")) return;

    var card = document.createElement("div");
    card.id = "vsp-ci-gate-global-card";
    card.className = "vsp-table-card vsp-ci-gate-card vsp-fadein vsp-fadein-delay-3";
    card.style.position = "fixed";
    card.style.right = "24px";
    card.style.bottom = "24px";
    card.style.width = "320px";
    card.style.zIndex = "9999";
    card.style.boxShadow = "0 18px 45px rgba(15,23,42,0.9)";

    var header = document.createElement("div");
    header.className = "vsp-table-card-header";

    var title = document.createElement("div");
    title.className = "vsp-table-card-title";
    title.textContent = "CI Gate – Latest Run";

    var statusWrap = document.createElement("div");
    statusWrap.id = "vsp-ci-gate-status-pill";

    header.appendChild(title);
    header.appendChild(statusWrap);
    card.appendChild(header);

    var body = document.createElement("div");
    body.style.fontSize = "12px";
    body.innerHTML =
      "<div style='color:#9ca3af;margin-bottom:4px;' id='vsp-ci-gate-run-id'>Run: N/A</div>" +
      "<div style='margin-bottom:8px;'>Total findings: <span style='font-size:20px;font-weight:600' id='vsp-ci-gate-total'>N/A</span></div>" +
      "<div style='display:flex;flex-wrap:wrap;gap:6px;font-size:11px;margin-bottom:6px;' id='vsp-ci-gate-sev-chips'></div>" +
      "<div style='font-size:11px;color:#6b7280;display:flex;justify-content:space-between;align-items:center;'>" +
      "<span>Source: <span id='vsp-ci-gate-source'>N/A</span></span>" +
      "<a href='#runs' style='color:#38bdf8;text-decoration:none;'>View in Runs</a>" +
      "</div>";
    card.appendChild(body);

    var close = document.createElement("button");
    close.textContent = "×";
    close.style.position = "absolute";
    close.style.top = "4px";
    close.style.right = "8px";
    close.style.border = "none";
    close.style.background = "transparent";
    close.style.color = "#9ca3af";
    close.style.cursor = "pointer";
    close.style.fontSize = "14px";
    close.addEventListener("click", function () {
      card.style.display = "none";
    });
    card.appendChild(close);

    document.body.appendChild(card);
    fetchCiGateLatest();
  }

  function fetchCiGateLatest() {
    var runIdEl = document.getElementById("vsp-ci-gate-run-id");
    var totalEl = document.getElementById("vsp-ci-gate-total");
    var chipsEl = document.getElementById("vsp-ci-gate-sev-chips");
    var sourceEl = document.getElementById("vsp-ci-gate-source");
    var pillWrap = document.getElementById("vsp-ci-gate-status-pill");
    if (!runIdEl || !totalEl || !chipsEl || !sourceEl || !pillWrap) return;

    fetch("/api/vsp/dashboard_v3")
      .then(function (r) { return r.json(); })
      .then(function (dash) {
        var runId = dash.latest_run_id || "N/A";
        var total = dash.total_findings || 0;
        var sev = dash.by_severity || {};
        var score = dash.security_posture_score || 0;

        runIdEl.textContent = "Run: " + runId;
        totalEl.textContent = total;
        sourceEl.textContent = "FULL_EXT (dashboard_v3)";

        var status = "OK";
        var cls = "vsp-badge vsp-badge-green";
        if (score < 30) { status = "FAILED"; cls = "vsp-badge vsp-badge-red"; }
        else if (score < 60) { status = "WARN"; cls = "vsp-badge vsp-badge-amber"; }

        pillWrap.innerHTML = "";
        var pill = document.createElement("span");
        pill.className = cls;
        pill.textContent = status;
        pillWrap.appendChild(pill);

        chipsEl.innerHTML = "";
        var order = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "TRACE"];
        var labels = ["C", "H", "M", "L", "I", "T"];
        order.forEach(function (k, idx) {
          var val = sev[k] || 0;
          var chip = document.createElement("span");
          chip.style.borderRadius = "999px";
          chip.style.border = "1px solid rgba(148,163,184,0.6)";
          chip.style.padding = "2px 6px";
          chip.style.fontSize = "11px";
          chip.textContent = labels[idx] + ": " + val;
          chipsEl.appendChild(chip);
        });
      })
      .catch(function () {
        runIdEl.textContent = "Run: N/A";
        totalEl.textContent = "N/A";
        sourceEl.textContent = "N/A";
      });
  }

  /* ------------ RUNS TAB (KPI + filter + badges) ------------ */

  function enhanceRunsTab(root) {
    if (!root) return;

    var table = root.querySelector("table");
    if (!table) return;
    var tbody = table.querySelector("tbody");
    if (!tbody) return;

    // KPI grid
    if (!root.querySelector(".vsp-runs-kpi-grid")) {
      var grid = document.createElement("div");
      grid.className = "vsp-runs-kpi-grid";
      grid.style.display = "grid";
      grid.style.gridTemplateColumns = "repeat(4,minmax(0,1fr))";
      grid.style.gap = "16px";
      grid.style.marginBottom = "18px";

      function makeKpi(id, label, sub) {
        var card = document.createElement("div");
        card.className = "vsp-kpi-card vsp-fadein vsp-fadein-delay-2";
        card.id = id;

        var title = document.createElement("div");
        title.className = "vsp-kpi-title";
        title.textContent = label;

        var value = document.createElement("div");
        value.className = "vsp-kpi-value";
        value.textContent = "--";

        var desc = document.createElement("div");
        desc.className = "vsp-kpi-sub";
        desc.textContent = sub;

        card.appendChild(title);
        card.appendChild(value);
        card.appendChild(desc);
        return card;
      }

      grid.appendChild(makeKpi("vsp-runs-kpi-total", "TOTAL RUNS", "Tổng số lần scan"));
      grid.appendChild(makeKpi("vsp-runs-kpi-lastn", "LAST N RUNS", "kpi.last_n"));
      grid.appendChild(makeKpi("vsp-runs-kpi-avg", "AVG FINDINGS / RUN", "Trung bình trên last N"));
      grid.appendChild(makeKpi("vsp-runs-kpi-latest", "LATEST GATE", "Status / Gate latest run"));

      table.parentNode.insertBefore(grid, table);
      fetchRunsGateSummaryKpi();
    }

    // Filter bar
    if (!root.querySelector(".vsp-runs-filter-bar")) {
      var container = document.createElement("div");
      container.className = "vsp-filter-bar vsp-runs-filter-bar";

      var inpId = document.createElement("input");
      inpId.className = "vsp-filter-input";
      inpId.placeholder = "Filter Run ID...";
      container.appendChild(inpId);

      var inpStatus = document.createElement("input");
      inpStatus.className = "vsp-filter-input";
      inpStatus.placeholder = "Filter Status / Gate...";
      container.appendChild(inpStatus);

      table.parentNode.insertBefore(container, table);

      function applyFilter() {
        var qId = inpId.value.toLowerCase();
        var qStatus = inpStatus.value.toLowerCase();

        Array.from(tbody.rows).forEach(function (row) {
          var text = row.innerText.toLowerCase();
          var ok = true;
          if (qId && text.indexOf(qId) === -1) ok = false;
          if (qStatus && text.indexOf(qStatus) === -1) ok = false;
          row.style.display = ok ? "" : "none";
        });
      }

      inpId.addEventListener("input", applyFilter);
      inpStatus.addEventListener("input", applyFilter);
    }

    // Badges cho cột cuối
    Array.from(tbody.rows).forEach(function (row) {
      var cells = row.children;
      if (!cells.length) return;
      var last = cells[cells.length - 1];
      if (!last || last.querySelector(".vsp-badge")) return;

      var text = (last.textContent || "").trim();
      if (!text) return;

      var upper = text.toUpperCase();
      var cls = null;

      if (upper.includes("GREEN") || upper === "DONE" || upper === "PASS") {
        cls = "vsp-badge vsp-badge-green";
      } else if (upper.includes("AMBER") || upper === "WARN" || upper.includes("WARNING")) {
        cls = "vsp-badge vsp-badge-amber";
      } else if (upper.includes("RED") || upper === "FAIL" || upper.includes("ERROR")) {
        cls = "vsp-badge vsp-badge-red";
      }

      if (!cls) return;

      last.textContent = "";
      var span = document.createElement("span");
      span.className = cls;
      span.textContent = text;
      last.appendChild(span);
    });
  }

  function fetchRunsGateSummaryKpi() {
    var elTotal = document.querySelector("#vsp-runs-kpi-total .vsp-kpi-value");
    var elLastN = document.querySelector("#vsp-runs-kpi-lastn .vsp-kpi-value");
    var elAvg   = document.querySelector("#vsp-runs-kpi-avg .vsp-kpi-value");
    var elLatest= document.querySelector("#vsp-runs-kpi-latest .vsp-kpi-value");
    if (!elTotal || !elLastN || !elAvg || !elLatest) return;

    fetch("/api/vsp/runs_index_v3?limit=40")
      .then(function (r) { return r.json(); })
      .then(function (data) {
        var items = data.items || [];
        var kpi = data.kpi || {};

        var totalRuns = kpi.total_runs || items.length || 0;
        var lastN = kpi.last_n || 0;
        var avgFind = kpi.avg_findings_per_run_last_n || null;

        var latest = items[0] || {};
        var latestStatus = (latest.status || "N/A");
        if (latest.ci_gate_status) latestStatus += " / " + latest.ci_gate_status;

        elTotal.textContent = totalRuns;
        elLastN.textContent = lastN || "N/A";
        elAvg.textContent   = avgFind != null ? Math.round(avgFind) : "N/A";
        elLatest.textContent= latestStatus;
      })
      .catch(function () {
        elTotal.textContent = elLastN.textContent = elAvg.textContent = elLatest.textContent = "N/A";
      });
  }

  /* ------------ DATA SOURCE (summary + mini chart + filter) ------------ */

  var dsCharts = { sev: null, tool: null };

  function enhanceDatasourceTab(root) {
    if (!root) return;
    var table = root.querySelector("table");
    if (!table) return;
    var tbody = table.querySelector("tbody");
    if (!tbody) return;

    // Summary card + mini canvases
    if (!root.querySelector(".vsp-ds-summary-card")) {
      var card = document.createElement("div");
      card.className = "vsp-table-card vsp-ds-summary-card vsp-fadein vsp-fadein-delay-2";

      var header = document.createElement("div");
      header.className = "vsp-table-card-header";

      var title = document.createElement("div");
      title.className = "vsp-table-card-title";
      title.textContent = "Data Source summary";

      var sub = document.createElement("div");
      sub.className = "vsp-table-card-sub";
      sub.textContent = "Mini chart & thống kê nhanh từ /api/vsp/datasource_v2 (limit=500).";

      header.appendChild(title); header.appendChild(sub);
      card.appendChild(header);

      var inner = document.createElement("div");
      inner.style.display = "grid";
      inner.style.gridTemplateColumns = "minmax(0,1.5fr) minmax(0,1fr)";
      inner.style.gap = "16px";

      var left = document.createElement("div");
      left.innerHTML =
        "<table class='vsp-table-compact'>" +
        "<thead><tr><th>METRIC</th><th>VALUE</th></tr></thead>" +
        "<tbody id='vsp-ds-summary-body'><tr><td colspan='2'>Đang tải...</td></tr></tbody>" +
        "</table>";

      var right = document.createElement("div");
      right.innerHTML =
        "<div style='height:110px;margin-bottom:8px;'><canvas id='vsp-ds-summary-sev-canvas'></canvas></div>" +
        "<div style='height:110px;'><canvas id='vsp-ds-summary-tool-canvas'></canvas></div>";

      inner.appendChild(left);
      inner.appendChild(right);
      card.appendChild(inner);

      var parent = table.parentNode || root;
      parent.insertBefore(card, table);

      fetchDatasourceSummaryAndCharts();
    }

    // Filter bar
    if (!root.querySelector(".vsp-ds-filter-bar")) {
      var container = document.createElement("div");
      container.className = "vsp-filter-bar vsp-ds-filter-bar";

      var inpSeverity = document.createElement("input");
      inpSeverity.className = "vsp-filter-input";
      inpSeverity.placeholder = "Severity (CRITICAL/HIGH/...)";
      container.appendChild(inpSeverity);

      var inpTool = document.createElement("input");
      inpTool.className = "vsp-filter-input";
      inpTool.placeholder = "Tool (semgrep, kics, ...)";
      container.appendChild(inpTool);

      table.parentNode.insertBefore(container, table);

      function applyFilter() {
        var qSev = inpSeverity.value.toLowerCase();
        var qTool = inpTool.value.toLowerCase();

        Array.from(tbody.rows).forEach(function (row) {
          var text = row.innerText.toLowerCase();
          var ok = true;
          if (qSev && text.indexOf(qSev) === -1) ok = false;
          if (qTool && text.indexOf(qTool) === -1) ok = false;
          row.style.display = ok ? "" : "none";
        });
      }

      inpSeverity.addEventListener("input", applyFilter);
      inpTool.addEventListener("input", applyFilter);
    }
  }

  function fetchDatasourceSummaryAndCharts() {
    var tbody = document.getElementById("vsp-ds-summary-body");
    if (!tbody) return;

    fetch("/api/vsp/datasource_v2?limit=500")
      .then(function (r) { return r.json(); })
      .then(function (data) {
        var items = data.items || [];

        var total = items.length;
        var bySev = {};
        var byTool = {};

        items.forEach(function (it) {
          var s = it.severity || "UNKNOWN";
          var t = it.tool || "UNKNOWN";
          bySev[s] = (bySev[s] || 0) + 1;
          byTool[t] = (byTool[t] || 0) + 1;
        });

        var sevParts = Object.keys(bySev).sort().map(function (k) {
          return k + ": " + bySev[k];
        });

        var toolParts = Object.keys(byTool).sort(function (a, b) {
          return byTool[b] - byTool[a];
        }).slice(0, 6).map(function (k) {
          return k + ": " + byTool[k];
        });

        tbody.innerHTML = "";
        function row(k, v) {
          var tr = document.createElement("tr");
          tr.innerHTML = "<td>" + k + "</td><td>" + v + "</td>";
          tbody.appendChild(tr);
        }

        row("Total findings (limit 500)", total);
        row("By severity", sevParts.join(" · "));
        row("Top tools", toolParts.join(" · "));

        renderDatasourceCharts(bySev, byTool);
      })
      .catch(function () {
        tbody.innerHTML = "<tr><td colspan='2'>Lỗi tải dữ liệu.</td></tr>";
      });
  }

  function renderDatasourceCharts(bySev, byTool) {
    if (typeof Chart === "undefined") {
      console.warn("[VSP_V28] Chart.js not available – skip DS mini charts");
      return;
    }

    var sevCanvas = document.getElementById("vsp-ds-summary-sev-canvas");
    var toolCanvas = document.getElementById("vsp-ds-summary-tool-canvas");
    if (!sevCanvas || !toolCanvas) return;

    var sevLabels = Object.keys(bySev);
    var sevData = sevLabels.map(function (k) { return bySev[k]; });

    var toolLabels = Object.keys(byTool).sort(function (a, b) {
      return byTool[b] - byTool[a];
    }).slice(0, 6);
    var toolData = toolLabels.map(function (k) { return byTool[k]; });

    if (dsCharts.sev) dsCharts.sev.destroy();
    if (dsCharts.tool) dsCharts.tool.destroy();

    dsCharts.sev = new Chart(sevCanvas.getContext("2d"), {
      type: "doughnut",
      data: {
        labels: sevLabels,
        datasets: [{ data: sevData }]
      },
      options: {
        plugins: { legend: { display: false } },
        maintainAspectRatio: false
      }
    });

    dsCharts.tool = new Chart(toolCanvas.getContext("2d"), {
      type: "bar",
      data: {
        labels: toolLabels,
        datasets: [{ data: toolData }]
      },
      options: {
        plugins: { legend: { display: false } },
        maintainAspectRatio: false,
        scales: { x: { ticks: { autoSkip: false, maxRotation: 60, minRotation: 30 } } }
      }
    });
  }

  /* ------------ SETTINGS ------------ */

  function enhanceSettingsTab(root) {
    if (!root) return;
    if (root.querySelector(".vsp-settings-summary-card")) return;

    var pre = root.querySelector("pre");
    if (!pre) return;

    var data = safeParseJSON(pre.textContent.trim());
    if (!data || typeof data !== "object") return;

    var settings = data.settings || {};

    var sumCard = document.createElement("div");
    sumCard.className = "vsp-table-card vsp-settings-summary-card vsp-fadein vsp-fadein-delay-2";

    var header = document.createElement("div");
    header.className = "vsp-table-card-header";
    var title = document.createElement("div");
    title.className = "vsp-table-card-title";
    title.textContent = "Settings summary";
    var sub = document.createElement("div");
    sub.className = "vsp-table-card-sub";
    sub.textContent = "Tổng quan cấu hình từ settings_ui_v1.";
    header.appendChild(title); header.appendChild(sub);
    sumCard.appendChild(header);

    var table = document.createElement("table");
    table.className = "vsp-table-compact";
    var rowsHtml = "";
    Object.keys(data).forEach(function (k, idx) {
      var v = data[k];
      var type = Array.isArray(v) ? "array" : typeof v;
      var extra = "";
      if (Array.isArray(v)) extra = v.length + " item(s)";
      else if (v && typeof v === "object") extra = Object.keys(v).length + " key(s)";
      rowsHtml += "<tr><td>" + (idx + 1) + "</td><td>" + k + "</td><td>" + type + "</td><td>" + extra + "</td></tr>";
    });
    table.innerHTML =
      "<thead><tr><th>#</th><th>Key</th><th>Type</th><th>Detail</th></tr></thead><tbody>" + rowsHtml + "</tbody>";
    sumCard.appendChild(table);

    var grid = document.createElement("div");
    grid.className = "vsp-dashboard-extras-grid vsp-fadein vsp-fadein-delay-3";

    // Scan config
    var scanCard = document.createElement("div");
    scanCard.className = "vsp-table-card";
    var scanHeader = document.createElement("div");
    scanHeader.className = "vsp-table-card-header";
    var scanTitle = document.createElement("div");
    scanTitle.className = "vsp-table-card-title";
    scanTitle.textContent = "Scan config (paths & exclude)";
    var scanSub = document.createElement("div");
    scanSub.className = "vsp-table-card-sub";
    scanSub.textContent = "Thư mục gốc, thư mục quét và pattern loại trừ.";
    scanHeader.appendChild(scanTitle); scanHeader.appendChild(scanSub);
    scanCard.appendChild(scanHeader);
    var scanTable = document.createElement("table");
    scanTable.className = "vsp-table-compact";
    var scan = settings.scan || {};
    var roots = scan.scan_roots || scan.roots || [];
    var excludes = scan.exclude_patterns || scan.excludes || [];
    if (!scan.project_root && !roots.length && !excludes.length) {
      scanTable.innerHTML = "<tbody><tr><td>Chưa cấu hình scan paths trong settings.scan.</td></tr></tbody>";
    } else {
      var sRows = "";
      sRows += "<tr><td>Project root</td><td>" + (scan.project_root || "N/A") + "</td></tr>";
      sRows += "<tr><td>Scan roots</td><td>" + (roots.length ? roots.join(', ') : "N/A") + "</td></tr>";
      sRows += "<tr><td>Excludes</td><td>" + (excludes.length ? excludes.join(', ') : "N/A") + "</td></tr>";
      scanTable.innerHTML =
        "<thead><tr><th>Field</th><th>Value</th></tr></thead><tbody>" + sRows + "</tbody>";
    }
    scanCard.appendChild(scanTable);

    // Tools
    var toolsCard = document.createElement("div");
    toolsCard.className = "vsp-table-card";
    var toolsHeader = document.createElement("div");
    toolsHeader.className = "vsp-table-card-header";
    var toolsTitle = document.createElement("div");
    toolsTitle.className = "vsp-table-card-title";
    toolsTitle.textContent = "Tool stack";
    var toolsSub = document.createElement("div");
    toolsSub.className = "vsp-table-card-sub";
    toolsSub.textContent = "Danh sách tool ON/OFF & profile.";
    toolsHeader.appendChild(toolsTitle); toolsHeader.appendChild(toolsSub);
    toolsCard.appendChild(toolsHeader);
    var toolsTable = document.createElement("table");
    toolsTable.className = "vsp-table-compact";
    var tools = settings.tools || {};
    var toolKeys = Object.keys(tools);
    if (!toolKeys.length) {
      toolsTable.innerHTML = "<tbody><tr><td>Chưa cấu hình tools trong settings.tools.</td></tr></tbody>";
    } else {
      var tRows = "";
      toolKeys.forEach(function (name) {
        var cfg = tools[name] || {};
        var enabled = cfg.enabled === false ? "OFF" : "ON";
        var profile = cfg.profile || cfg.mode || "-";
        tRows += "<tr><td>" + name + "</td><td>" + enabled + "</td><td>" + profile + "</td></tr>";
      });
      toolsTable.innerHTML =
        "<thead><tr><th>Tool</th><th>Enabled</th><th>Profile/Mode</th></tr></thead><tbody>" + tRows + "</tbody>";
    }
    toolsCard.appendChild(toolsTable);

    // CI Gate
    var gateCard = document.createElement("div");
    gateCard.className = "vsp-table-card";
    var gateHeader = document.createElement("div");
    gateHeader.className = "vsp-table-card-header";
    var gateTitle = document.createElement("div");
    gateTitle.className = "vsp-table-card-title";
    gateTitle.textContent = "CI/CD Gate policy";
    var gateSub = document.createElement("div");
    gateSub.className = "vsp-table-card-sub";
    gateSub.textContent = "Ngưỡng RED/AMBER/GREEN từ settings.ci_gate.";
    gateHeader.appendChild(gateTitle); gateHeader.appendChild(gateSub);
    gateCard.appendChild(gateHeader);
    var gateTable = document.createElement("table");
    gateTable.className = "vsp-table-compact";
    var ciGate = settings.ci_gate || {};
    var gateKeys = Object.keys(ciGate);
    if (!gateKeys.length) {
      gateTable.innerHTML = "<tbody><tr><td>Chưa cấu hình CI/CD Gate trong settings.ci_gate.</td></tr></tbody>";
    } else {
      var gRows = "";
      gateKeys.forEach(function (k) {
        var v = ciGate[k];
        var val;
        if (Array.isArray(v)) val = v.join(", ");
        else if (v && typeof v === "object") val = JSON.stringify(v);
        else val = String(v);
        gRows += "<tr><td>" + k + "</td><td>" + val + "</td></tr>";
      });
      gateTable.innerHTML =
        "<thead><tr><th>Key</th><th>Value</th></tr></thead><tbody>" + gRows + "</tbody>";
    }
    gateCard.appendChild(gateTable);

    grid.appendChild(scanCard);
    grid.appendChild(toolsCard);
    grid.appendChild(gateCard);

    pre.parentNode.insertBefore(sumCard, pre);
    pre.parentNode.insertBefore(grid, pre);
  }

  /* ------------ RULE OVERRIDES ------------ */

  function enhanceRulesTab(root) {
    if (!root) return;
    if (root.querySelector(".vsp-rules-summary-card")) return;

    var pre = root.querySelector("pre");
    if (!pre) return;

    var data = safeParseJSON(pre.textContent.trim());
    if (!data) return;

    var list = [];
    if (Array.isArray(data.items)) list = data.items;
    else if (Array.isArray(data.overrides)) list = data.overrides;
    else if (Array.isArray(data)) list = data;
    else if (typeof data === "object") {
      Object.keys(data).forEach(function (rid) {
        var v = data[rid];
        if (v && typeof v === "object") list.push(Object.assign({ rule_id: rid }, v));
      });
    }

    var card = document.createElement("div");
    card.className = "vsp-table-card vsp-rules-summary-card vsp-fadein vsp-fadein-delay-2";

    var header = document.createElement("div");
    header.className = "vsp-table-card-header";
    var title = document.createElement("div");
    title.className = "vsp-table-card-title";
    title.textContent = "Rule overrides summary";
    var sub = document.createElement("div");
    sub.className = "vsp-table-card-sub";
    sub.textContent = list.length
      ? "Các rule đang bị override severity / scope (rule_overrides_ui_v1)."
      : "Chưa có rule nào bị override (rule_overrides_ui_v1).";
    header.appendChild(title); header.appendChild(sub);
    card.appendChild(header);

    var table = document.createElement("table");
    table.className = "vsp-table-compact";
    if (!list.length) {
      table.innerHTML = "<tbody><tr><td>Không có overrides.</td></tr></tbody>";
    } else {
      var bodyHtml = "";
      list.slice(0, 50).forEach(function (ov, idx) {
        var rid = ov.rule_id || ov.id || "";
        var sev = ov.new_severity || ov.severity || "";
        var scope = ov.scope || ov.path || ov.module || "";
        bodyHtml += "<tr><td>" + (idx + 1) + "</td><td>" + rid + "</td><td>" + sev + "</td><td>" + scope + "</td></tr>";
      });
      table.innerHTML =
        "<thead><tr><th>#</th><th>Rule</th><th>Severity</th><th>Scope</th></tr></thead><tbody>" + bodyHtml + "</tbody>";
    }

    card.appendChild(table);
    pre.parentNode.insertBefore(card, pre);
  }

  /* ------------ BOOTSTRAP ------------ */

  function bootstrap() {
    try {
      wrapShellAndHeaders();
      animateDashboardKpis();
      buildDashboardExtras();
      createGlobalCiGateCard();
    } catch (e) {
      console.warn("[VSP_V28] bootstrap error", e);
    }

    observeOnce("vsp-runs-main", enhanceRunsTab);
    observeOnce("vsp-datasource-main", enhanceDatasourceTab);
    observeOnce("vsp-settings-main", enhanceSettingsTab);
    observeOnce("vsp-rules-main", enhanceRulesTab);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", bootstrap);
  } else {
    bootstrap();
  }

  window.addEventListener("hashchange", function () {
    setTimeout(bootstrap, 200);
  });
})();
JS

echo "$LOG_PREFIX [OK] Đã ghi JS V2.8 vào $JS"
echo "$LOG_PREFIX Hoàn tất patch UI V2.8 – KPI + DS mini charts + global CI Gate card."
