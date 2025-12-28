#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CSS="$ROOT/static/css/vsp_v25_polish.css"
JS="$ROOT/static/js/vsp_ui_extras_v25.js"
LOG_PREFIX="[VSP_V251]"

echo "$LOG_PREFIX ROOT = $ROOT"

if [ -f "$CSS" ]; then
  BAK_CSS="$CSS.bak_v25_$(date +%Y%m%d_%H%M%S)"
  cp "$CSS" "$BAK_CSS"
  echo "$LOG_PREFIX [BACKUP] $CSS -> $BAK_CSS"
fi

if [ -f "$JS" ]; then
  BAK_JS="$JS.bak_v25_$(date +%Y%m%d_%H%M%S)"
  cp "$JS" "$BAK_JS"
  echo "$LOG_PREFIX [BACKUP] $JS -> $BAK_JS"
fi

########################################
# Ghi lại CSS – V2.5.1 (polish thêm)
########################################
cat > "$CSS" << 'CSS'
/* VSP 2025 – V2.5.1 Polish MAX
 * - Shell layout chuẩn 1440px
 * - Card glassmorphism mềm hơn
 * - Table nâng cao
 * - Badge Gate
 * - Filter bar
 * - Animation fade-in nhẹ
 */

:root {
  --vsp-shell-max-width: 1440px;
  --vsp-shell-padding-x: 32px;
  --vsp-shell-padding-y: 24px;
  --vsp-card-radius: 18px;
  --vsp-card-shadow-soft: 0 20px 50px rgba(15, 23, 42, 0.8);
  --vsp-anim-duration: 0.45s;
}

/* Shell ôm content từng tab */
.vsp-main-shell {
  max-width: var(--vsp-shell-max-width);
  margin: 0 auto;
  padding: var(--vsp-shell-padding-y) var(--vsp-shell-padding-x) 40px;
  box-sizing: border-box;
}

/* Header cho từng tab (chèn bằng JS) */
.vsp-tab-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  margin-bottom: 18px;
}

.vsp-tab-header-title {
  font-size: 20px;
  font-weight: 600;
  letter-spacing: 0.02em;
  color: #e5e7eb;
}

.vsp-tab-header-sub {
  font-size: 12px;
  color: #9ca3af;
}

/* Card style chung – glassmorphism */
.vsp-card,
.vsp-kpi-card,
.vsp-chart-card,
.vsp-table-card {
  border-radius: var(--vsp-card-radius);
  background: radial-gradient(circle at top left, rgba(15, 118, 255, 0.16), transparent 55%),
              radial-gradient(circle at bottom right, rgba(236, 72, 153, 0.18), transparent 55%),
              #020617;
  box-shadow: var(--vsp-card-shadow-soft);
  border: 1px solid rgba(148, 163, 184, 0.22);
  backdrop-filter: blur(18px);
  transition:
    transform 180ms ease-out,
    box-shadow 180ms ease-out,
    border-color 180ms ease-out,
    background 220ms ease-out;
}

.vsp-card:hover,
.vsp-kpi-card:hover,
.vsp-chart-card:hover,
.vsp-table-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 26px 65px rgba(15, 23, 42, 0.95);
  border-color: rgba(129, 140, 248, 0.7);
}

/* Table card */
.vsp-table-card {
  padding: 16px 20px 14px;
}

.vsp-table-card-header {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  margin-bottom: 10px;
}

.vsp-table-card-title {
  font-size: 13px;
  font-weight: 600;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: #e5e7eb;
}

.vsp-table-card-sub {
  font-size: 12px;
  color: #9ca3af;
}

/* Compact table */
.vsp-table-compact {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
}

.vsp-table-compact thead {
  text-transform: uppercase;
  letter-spacing: 0.08em;
  font-size: 11px;
  color: #9ca3af;
}

.vsp-table-compact th,
.vsp-table-compact td {
  padding: 6px 8px;
  border-bottom: 1px solid rgba(30, 64, 175, 0.55);
  white-space: nowrap;
}

.vsp-table-compact tbody tr:nth-child(even) {
  background: rgba(15, 23, 42, 0.65);
}

.vsp-table-compact tbody tr:hover {
  background: rgba(59, 130, 246, 0.2);
}

/* Dashboard extras grid */
.vsp-dashboard-extras-grid {
  display: grid;
  grid-template-columns: minmax(0, 2.2fr) minmax(0, 1.5fr);
  gap: 18px;
  margin-top: 20px;
}

/* Badge Gate / Delta */
.vsp-badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  border-radius: 999px;
  padding: 3px 10px;
  font-size: 11px;
  font-weight: 500;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.vsp-badge-green {
  background: rgba(22, 163, 74, 0.16);
  color: #bbf7d0;
  border: 1px solid rgba(22, 163, 74, 0.8);
}

.vsp-badge-amber {
  background: rgba(245, 158, 11, 0.16);
  color: #fed7aa;
  border: 1px solid rgba(245, 158, 11, 0.8);
}

.vsp-badge-red {
  background: rgba(239, 68, 68, 0.16);
  color: #fecaca;
  border: 1px solid rgba(239, 68, 68, 0.85);
}

/* Animation */
@keyframes vspFadeUp {
  from {
    opacity: 0;
    transform: translateY(12px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.vsp-fadein {
  opacity: 0;
  animation: vspFadeUp var(--vsp-anim-duration) ease-out forwards;
}

.vsp-fadein-delay-1 { animation-delay: 0.04s; }
.vsp-fadein-delay-2 { animation-delay: 0.10s; }
.vsp-fadein-delay-3 { animation-delay: 0.16s; }
.vsp-fadein-delay-4 { animation-delay: 0.22s; }
.vsp-fadein-delay-5 { animation-delay: 0.28s; }
.vsp-fadein-delay-6 { animation-delay: 0.34s; }

/* Filter bar cho Runs & DataSource */
.vsp-filter-bar {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-bottom: 12px;
}

.vsp-filter-input {
  background: #020617;
  border-radius: 999px;
  border: 1px solid rgba(148, 163, 184, 0.5);
  padding: 5px 11px;
  font-size: 12px;
  color: #e5e7eb;
  outline: none;
}

.vsp-filter-input::placeholder {
  color: #6b7280;
}

.vsp-filter-input:focus {
  border-color: rgba(129, 140, 248, 0.95);
  box-shadow: 0 0 0 1px rgba(129, 140, 248, 0.6);
}

/* Nhỏ lại trên mobile */
@media (max-width: 1024px) {
  :root {
    --vsp-shell-padding-x: 16px;
  }

  .vsp-dashboard-extras-grid {
    grid-template-columns: minmax(0, 1fr);
  }
}
CSS

echo "$LOG_PREFIX [OK] Đã ghi CSS V2.5.1 vào $CSS"

########################################
# Ghi lại JS – V2.5.1 (polish thêm)
########################################
cat > "$JS" << 'JS'
/**
 * VSP 2025 – UI Extras V2.5.1
 * - Shell spacing cho 5 tab
 * - Header đẹp cho từng tab
 * - Dashboard extras: Top High/Critical + Delta run
 * - Filter Runs / DataSource
 * - Re-bootstrap mỗi lần đổi hash tab
 */

(function () {
  console.log("[VSP_V251] vsp_ui_extras_v25.js (V2.5.1) loaded");

  function wrapShell() {
    [
      { id: "vsp-dashboard-main", title: "Dashboard", sub: "CIO-level Security Posture & Trends" },
      { id: "vsp-runs-main",      title: "Runs & Reports", sub: "Lịch sử quét, CI/CD Gate & Export báo cáo" },
      { id: "vsp-datasource-main",title: "Data Source", sub: "Chi tiết unified findings & mini analytics" },
      { id: "vsp-settings-main",  title: "Settings", sub: "Cấu hình tool stack & profile" },
      { id: "vsp-rules-main",     title: "Rule Overrides", sub: "Mapping & override rule/threshold" }
    ].forEach(function (cfg) {
      var el = document.getElementById(cfg.id);
      if (!el) return;

      if (!el.classList.contains("vsp-main-shell")) {
        el.classList.add("vsp-main-shell");
      }

      // Nếu chưa có header thì chèn vào đầu
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

        // chèn header lên trên cùng
        if (el.firstChild) {
          el.insertBefore(header, el.firstChild);
        } else {
          el.appendChild(header);
        }
      }
    });
  }

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

    if (root.querySelector(".vsp-dashboard-extras-grid")) {
      return; // đã build rồi
    }

    var extras = document.createElement("div");
    extras.className = "vsp-dashboard-extras-grid vsp-fadein vsp-fadein-delay-2";

    // Card Top High/Critical
    var cardTop = document.createElement("div");
    cardTop.className = "vsp-table-card";

    var headerTop = document.createElement("div");
    headerTop.className = "vsp-table-card-header";

    var hTitle = document.createElement("div");
    hTitle.className = "vsp-table-card-title";
    hTitle.textContent = "Top 10 High / Critical Findings";

    var hSub = document.createElement("div");
    hSub.className = "vsp-table-card-sub";
    hSub.textContent = "Ưu tiên CRITICAL trước, lấy từ unified datasource_v2";

    headerTop.appendChild(hTitle);
    headerTop.appendChild(hSub);
    cardTop.appendChild(headerTop);

    var tableTop = document.createElement("table");
    tableTop.className = "vsp-table-compact";
    tableTop.innerHTML =
      "<thead><tr>" +
      "<th>#</th>" +
      "<th>Severity</th>" +
      "<th>Tool</th>" +
      "<th>Rule</th>" +
      "<th>CWE</th>" +
      "<th>File</th>" +
      "<th>Line</th>" +
      "</tr></thead>" +
      "<tbody id='vsp-dash-top-risks-body'><tr><td colspan='7'>Đang tải...</td></tr></tbody>";

    cardTop.appendChild(tableTop);

    // Card Delta run
    var cardDelta = document.createElement("div");
    cardDelta.className = "vsp-table-card";

    var headerDelta = document.createElement("div");
    headerDelta.className = "vsp-table-card-header";

    var dTitle = document.createElement("div");
    dTitle.className = "vsp-table-card-title";
    dTitle.textContent = "What changed since last run?";

    var dSub = document.createElement("div");
    dSub.className = "vsp-table-card-sub";
    dSub.textContent = "So sánh 2 lần quét gần nhất (Total Findings & xu hướng).";

    headerDelta.appendChild(dTitle);
    headerDelta.appendChild(dSub);
    cardDelta.appendChild(headerDelta);

    var tableDelta = document.createElement("table");
    tableDelta.className = "vsp-table-compact";
    tableDelta.innerHTML =
      "<thead><tr>" +
      "<th></th>" +
      "<th>Run ID</th>" +
      "<th>Total Findings</th>" +
      "<th>Time / Trend</th>" +
      "</tr></thead>" +
      "<tbody id='vsp-dash-delta-body'><tr><td colspan='4'>Đang tải...</td></tr></tbody>";

    cardDelta.appendChild(tableDelta);

    extras.appendChild(cardTop);
    extras.appendChild(cardDelta);

    root.appendChild(extras);

    fetchTopRisks();
    fetchDeltaRuns();
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
      .catch(function (err) {
        console.warn("[VSP_V251] fetchTopRisks error", err);
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

        var trLatest = document.createElement("tr");
        trLatest.innerHTML =
          "<td>Latest</td>" +
          "<td>" + (latest.run_id || "") + "</td>" +
          "<td>" + totalLatest + "</td>" +
          "<td>" + (latest.started_at || latest.created_at || "") + "</td>";
        tbody.appendChild(trLatest);

        var trPrev = document.createElement("tr");
        trPrev.innerHTML =
          "<td>Previous</td>" +
          "<td>" + (prev.run_id || "") + "</td>" +
          "<td>" + totalPrev + "</td>" +
          "<td>" + (prev.started_at || prev.created_at || "") + "</td>";
        tbody.appendChild(trPrev);

        var trDelta = document.createElement("tr");
        var tdLabel = document.createElement("td");
        tdLabel.textContent = "Delta";

        var tdEmptyRun = document.createElement("td");
        tdEmptyRun.textContent = "";

        var tdDeltaVal = document.createElement("td");
        tdDeltaVal.textContent = (delta >= 0 ? "+" : "") + delta;

        var tdBadgeCell = document.createElement("td");
        tdBadgeCell.appendChild(badge);

        trDelta.appendChild(tdLabel);
        trDelta.appendChild(tdEmptyRun);
        trDelta.appendChild(tdDeltaVal);
        trDelta.appendChild(tdBadgeCell);

        tbody.appendChild(trDelta);
      })
      .catch(function (err) {
        console.warn("[VSP_V251] fetchDeltaRuns error", err);
        tbody.innerHTML = "<tr><td colspan='4'>Lỗi tải dữ liệu.</td></tr>";
      });
  }

  function enhanceRunsFilter() {
    var root = document.getElementById("vsp-runs-main");
    if (!root) return;

    var table = root.querySelector("table");
    if (!table || table.dataset.vspFilterAdded === "1") return;

    table.dataset.vspFilterAdded = "1";

    var tbody = table.querySelector("tbody");
    if (!tbody) return;

    var container = document.createElement("div");
    container.className = "vsp-filter-bar";

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

  function enhanceDatasourceFilter() {
    var root = document.getElementById("vsp-datasource-main");
    if (!root) return;

    var table = root.querySelector("table");
    if (!table || table.dataset.vspFilterAdded === "1") return;

    table.dataset.vspFilterAdded = "1";

    var tbody = table.querySelector("tbody");
    if (!tbody) return;

    var container = document.createElement("div");
    container.className = "vsp-filter-bar";

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

  function bootstrap() {
    try {
      wrapShell();
      animateDashboardKpis();
      buildDashboardExtras();
    } catch (e) {
      console.warn("[VSP_V251] bootstrap dashboard error", e);
    }

    setTimeout(function () {
      try { enhanceRunsFilter(); } catch (e) { console.warn("[VSP_V251] runs filter error", e); }
      try { enhanceDatasourceFilter(); } catch (e) { console.warn("[VSP_V251] datasource filter error", e); }
    }, 800);
  }

  // Initial load
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", bootstrap);
  } else {
    bootstrap();
  }

  // Re-run khi đổi tab (hash change)
  window.addEventListener("hashchange", function () {
    setTimeout(function () {
      bootstrap();
    }, 200);
  });
})();
JS

echo "$LOG_PREFIX [OK] Đã ghi JS V2.5.1 vào $JS"
echo "$LOG_PREFIX Hoàn tất patch UI V2.5.1 – polish full spacing + animation + bảng nâng cao."
