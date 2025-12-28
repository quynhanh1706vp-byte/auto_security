#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS_DIR="$ROOT/static/js"
CSS_MAIN="$ROOT/static/css/vsp_main.css"

echo "[V2_UI] ROOT = $ROOT"

backup_if_exists() {
  local f="$1"
  if [ -f "$f" ]; then
    local b="${f}.bak_v2_$(date +%Y%m%d_%H%M%S)"
    cp "$f" "$b"
    echo "[V2_UI] Backup $f -> $b"
  fi
}

# --------------------------------------------------
# 1) CSS: theme tổng cho 5 tab + bảng + badge + filter
# --------------------------------------------------
if [ -f "$CSS_MAIN" ]; then
  backup_if_exists "$CSS_MAIN"
  cat >> "$CSS_MAIN" << 'CSS'

/* ==== VSP UI 2025 – V2 THEME PATCH (global) ==== */

#vsp-tab-dashboard,
#vsp-tab-runs,
#vsp-tab-datasource,
#vsp-tab-settings,
#vsp-tab-rules {
  padding: 24px 32px 40px;
  box-sizing: border-box;
}

/* Section header + title */
.vsp-section-header {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 16px;
}

.vsp-section-title {
  font-size: 20px;
  font-weight: 600;
  letter-spacing: 0.02em;
  color: #e5e7eb;
  margin: 0;
}

.vsp-section-subtitle {
  font-size: 13px;
  color: #9ca3af;
  margin: 4px 0 0 0;
}

/* Card chung */
.vsp-card {
  background: linear-gradient(135deg, rgba(15,23,42,0.96), rgba(15,23,42,0.85));
  border-radius: 16px;
  border: 1px solid rgba(148,163,184,0.18);
  box-shadow: 0 18px 50px rgba(15,23,42,0.75);
  padding: 18px 20px;
  margin-bottom: 18px;
}

/* Card bảng */
.vsp-card-table {
  padding: 0;
  overflow: hidden;
}

/* Nút ghost nhỏ (refresh, v.v.) */
.vsp-section-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

.vsp-btn {
  border-radius: 999px;
  padding: 6px 14px;
  font-size: 13px;
  border: 1px solid rgba(148,163,184,0.35);
  background: rgba(15,23,42,0.7);
  color: #e5e7eb;
  cursor: pointer;
  outline: none;
  transition: background 0.15s ease, border-color 0.15s ease, transform 0.08s ease;
}

.vsp-btn:hover {
  background: rgba(30,64,175,0.9);
  border-color: rgba(129,140,248,0.9);
  transform: translateY(-0.5px);
}

/* Bảng chung cho Runs & DataSource */
#vsp-tab-runs table,
#vsp-tab-datasource table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
  color: #e5e7eb;
  table-layout: fixed;
}

#vsp-tab-runs thead,
#vsp-tab-datasource thead {
  background: linear-gradient(90deg, rgba(15,23,42,0.95), rgba(30,64,175,0.45));
}

#vsp-tab-runs th,
#vsp-tab-datasource th {
  text-align: left;
  padding: 10px 14px;
  font-weight: 500;
  letter-spacing: 0.03em;
  text-transform: uppercase;
  font-size: 11px;
  color: #cbd5f5;
  border-bottom: 1px solid rgba(148,163,184,0.35);
}

#vsp-tab-runs td,
#vsp-tab-datasource td {
  padding: 8px 14px;
  border-bottom: 1px solid rgba(31,41,55,0.9);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

#vsp-tab-runs tbody tr:nth-child(even),
#vsp-tab-datasource tbody tr:nth-child(even) {
  background: rgba(15,23,42,0.86);
}

#vsp-tab-runs tbody tr:nth-child(odd),
#vsp-tab-datasource tbody tr:nth-child(odd) {
  background: rgba(15,23,42,0.75);
}

#vsp-tab-runs tbody tr:hover,
#vsp-tab-datasource tbody tr:hover {
  background: radial-gradient(circle at top left, rgba(56,189,248,0.18), rgba(15,23,42,0.9));
}

/* Cột specific */
.vsp-col-run-id {
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
}

.vsp-col-filename {
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
}

/* Empty / loading row */
.vsp-table-empty {
  text-align: center;
  font-size: 13px;
  padding: 18px 14px;
  color: #9ca3af;
}

/* Badge chung */
.vsp-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 2px 10px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 500;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  white-space: nowrap;
}

/* Badge CI/CD gate */
.vsp-badge-gate-green {
  background: rgba(22,163,74,0.15);
  border: 1px solid rgba(34,197,94,0.95);
  color: #4ade80;
}

.vsp-badge-gate-amber {
  background: rgba(234,179,8,0.13);
  border: 1px solid rgba(250,204,21,0.95);
  color: #facc15;
}

.vsp-badge-gate-red {
  background: rgba(248,113,113,0.18);
  border: 1px solid rgba(248,113,113,0.98);
  color: #fecaca;
}

.vsp-badge-gate-na {
  background: rgba(75,85,99,0.2);
  border: 1px solid rgba(107,114,128,0.9);
  color: #e5e7eb;
}

/* Badge status run */
.vsp-badge-status-done {
  background: rgba(59,130,246,0.18);
  border: 1px solid rgba(96,165,250,0.95);
  color: #bfdbfe;
}

.vsp-badge-status-running {
  background: rgba(251,146,60,0.16);
  border: 1px solid rgba(251,146,60,0.98);
  color: #fed7aa;
}

/* Severity badge cho Data Source */
.vsp-badge-sev-critical {
  background: rgba(239,68,68,0.24);
  border: 1px solid rgba(248,113,113,0.98);
  color: #fee2e2;
}

.vsp-badge-sev-high {
  background: rgba(249,115,22,0.22);
  border: 1px solid rgba(251,146,60,0.95);
  color: #ffedd5;
}

.vsp-badge-sev-medium {
  background: rgba(234,179,8,0.18);
  border: 1px solid rgba(250,204,21,0.95);
  color: #fef3c7;
}

.vsp-badge-sev-low {
  background: rgba(59,130,246,0.18);
  border: 1px solid rgba(96,165,250,0.95);
  color: #dbeafe;
}

.vsp-badge-sev-info {
  background: rgba(56,189,248,0.18);
  border: 1px solid rgba(56,189,248,0.98);
  color: #cffafe;
}

.vsp-badge-sev-trace {
  background: rgba(148,163,184,0.2);
  border: 1px solid rgba(148,163,184,0.88);
  color: #e5e7eb;
}

/* Filter bar cho Data Source */
.vsp-ds-filters {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  margin-bottom: 12px;
}

.vsp-ds-filters label {
  font-size: 12px;
  color: #9ca3af;
  margin-right: 4px;
}

.vsp-input,
.vsp-select {
  background: rgba(15,23,42,0.9);
  border-radius: 999px;
  border: 1px solid rgba(55,65,81,0.9);
  padding: 5px 10px;
  font-size: 12px;
  color: #e5e7eb;
  outline: none;
  min-width: 120px;
}

.vsp-input::placeholder {
  color: #6b7280;
}

.vsp-input:focus,
.vsp-select:focus {
  border-color: rgba(129,140,248,0.9);
}

/* Scroll box cho bảng để không tràn viewport */
.vsp-table-wrapper {
  max-height: calc(100vh - 230px);
  overflow: auto;
}

/* JSON view trong Settings / Rules */
#vsp-tab-settings pre,
#vsp-tab-rules pre {
  margin: 0;
  font-size: 13px;
  line-height: 1.5;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
  color: #e5e7eb;
}

#vsp-tab-settings .vsp-card,
#vsp-tab-rules .vsp-card {
  padding: 16px 18px;
}

/* Dashboard text block tinh chỉnh nhẹ */
#vsp-dashboard-main pre {
  font-size: 13px;
  line-height: 1.5;
  color: #e5e7eb;
  background: rgba(15,23,42,0.8);
  border-radius: 14px;
  border: 1px solid rgba(31,41,55,0.9);
  padding: 14px 16px;
  margin-bottom: 18px;
}

CSS
else
  echo "[V2_UI][WARN] Không thấy $CSS_MAIN, bỏ qua patch CSS."
fi

# --------------------------------------------------
# 2) Runs & Reports tab – V2 (badge Gate + Status, theme đồng bộ)
# --------------------------------------------------
backup_if_exists "$JS_DIR/vsp_runs_tab_simple_v2.js"
cat > "$JS_DIR/vsp_runs_tab_simple_v2.js" << 'JS'
(function () {
  var API_URL = "/api/vsp/runs_index_v3?limit=40";

  function gateClass(gate) {
    if (!gate) return "vsp-badge vsp-badge-gate-na";
    var g = String(gate).toUpperCase();
    if (g === "GREEN" || g === "PASS") return "vsp-badge vsp-badge-gate-green";
    if (g === "AMBER" || g === "WARN" || g === "WARNING") return "vsp-badge vsp-badge-gate-amber";
    if (g === "RED" || g === "FAIL") return "vsp-badge vsp-badge-gate-red";
    return "vsp-badge vsp-badge-gate-na";
  }

  function gateLabel(gate) {
    if (!gate) return "N/A";
    return String(gate).toUpperCase();
  }

  function statusClass(status) {
    var s = (status || "").toString().toUpperCase();
    if (s === "DONE" || s === "FINISHED") return "vsp-badge vsp-badge-status-done";
    if (s === "RUNNING" || s === "IN_PROGRESS") return "vsp-badge vsp-badge-status-running";
    return "vsp-badge vsp-badge-status-done";
  }

  function statusLabel(status) {
    return status || "DONE";
  }

  function renderRuns(items) {
    var tbody = document.getElementById("vsp-runs-tbody");
    if (!tbody) return;

    if (!items || !items.length) {
      tbody.innerHTML = '<tr><td colspan="6" class="vsp-table-empty">Không có run nào trong runs_index_v3.</td></tr>';
      return;
    }

    var html = "";
    for (var i = 0; i < items.length; i++) {
      var it = items[i] || {};
      var runId = it.run_id || "";
      var type = it.type || "UNKNOWN";
      var started = it.started || "";
      var total = (typeof it.total_findings === "number") ? it.total_findings : (it.total_findings || "");
      var gate = it.ci_gate_status || it.gate_status || it.ci_status || "N/A";
      var status = it.status || "DONE";

      html += '<tr>' +
        '<td class="vsp-col-run-id" title="' + runId + '">' + runId + '</td>' +
        '<td>' + type + '</td>' +
        '<td>' + started + '</td>' +
        '<td>' + total + '</td>' +
        '<td><span class="' + gateClass(gate) + '">' + gateLabel(gate) + '</span></td>' +
        '<td><span class="' + statusClass(status) + '">' + statusLabel(status) + '</span></td>' +
        '</tr>';
    }

    tbody.innerHTML = html;
  }

  function loadRuns() {
    var tbody = document.getElementById("vsp-runs-tbody");
    if (tbody) {
      tbody.innerHTML = '<tr><td colspan="6" class="vsp-table-empty">Đang tải dữ liệu runs...</td></tr>';
    }

    fetch(API_URL, { cache: "no-store" })
      .then(function (res) { return res.json(); })
      .then(function (data) {
        console.log("[VSP_RUNS_TAB_V2] runs_index_v3 loaded.", data);
        var items = (data && data.items) || [];
        renderRuns(items);
      })
      .catch(function (err) {
        console.error("[VSP_RUNS_TAB_V2] Failed to load runs_index_v3:", err);
        if (tbody) {
          tbody.innerHTML = '<tr><td colspan="6" class="vsp-table-empty">Lỗi tải dữ liệu runs_index_v3.</td></tr>';
        }
      });
  }

  function hydratePane() {
    var pane = document.getElementById("vsp-tab-runs");
    if (!pane) {
      console.warn("[VSP_RUNS_TAB_V2] Không thấy #vsp-tab-runs");
      return;
    }

    pane.innerHTML =
      '<div class="vsp-section-header">' +
        '<div>' +
          '<h2 class="vsp-section-title">Runs &amp; Reports</h2>' +
          '<p class="vsp-section-subtitle">Lịch sử scan mới nhất từ SECURITY_BUNDLE (runs_index_v3)</p>' +
        '</div>' +
        '<div class="vsp-section-actions">' +
          '<button class="vsp-btn" id="vsp-runs-refresh-btn">Refresh</button>' +
        '</div>' +
      '</div>' +
      '<div class="vsp-card vsp-card-table">' +
        '<div class="vsp-table-wrapper">' +
          '<table class="vsp-table vsp-table-runs">' +
            '<thead>' +
              '<tr>' +
                '<th style="width: 32%;">RUN ID</th>' +
                '<th style="width: 10%;">TYPE</th>' +
                '<th style="width: 20%;">STARTED</th>' +
                '<th style="width: 12%;">TOTAL FINDINGS</th>' +
                '<th style="width: 13%;">CI/CD GATE</th>' +
                '<th style="width: 13%;">STATUS</th>' +
              '</tr>' +
            '</thead>' +
            '<tbody id="vsp-runs-tbody">' +
              '<tr><td colspan="6" class="vsp-table-empty">Đang tải dữ liệu runs...</td></tr>' +
            '</tbody>' +
          '</table>' +
        '</div>' +
      '</div>';

    var btn = document.getElementById("vsp-runs-refresh-btn");
    if (btn) {
      btn.addEventListener("click", function () {
        loadRuns();
      });
    }

    loadRuns();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", hydratePane);
  } else {
    hydratePane();
  }
})();
JS

# --------------------------------------------------
# 3) Data Source tab – V2 (filter Severity / Tool / Search)
# --------------------------------------------------
backup_if_exists "$JS_DIR/vsp_datasource_tab_simple_v2.js"
cat > "$JS_DIR/vsp_datasource_tab_simple_v2.js" << 'JS'
(function () {
  var API_URL = "/api/vsp/datasource_v2?limit=500";
  var ALL_ITEMS = [];

  function severityClass(sev) {
    if (!sev) return "vsp-badge vsp-badge-sev-info";
    var s = String(sev).toUpperCase();
    if (s === "CRITICAL") return "vsp-badge vsp-badge-sev-critical";
    if (s === "HIGH") return "vsp-badge vsp-badge-sev-high";
    if (s === "MEDIUM") return "vsp-badge vsp-badge-sev-medium";
    if (s === "LOW") return "vsp-badge vsp-badge-sev-low";
    if (s === "INFO") return "vsp-badge vsp-badge-sev-info";
    if (s === "TRACE") return "vsp-badge vsp-badge-sev-trace";
    return "vsp-badge vsp-badge-sev-info";
  }

  function severityLabel(sev) {
    return sev || "INFO";
  }

  function applyFilters() {
    var tbody = document.getElementById("vsp-ds-tbody");
    if (!tbody) return;

    if (!ALL_ITEMS || !ALL_ITEMS.length) {
      tbody.innerHTML = '<tr><td colspan="6" class="vsp-table-empty">Không có findings nào trong datasource_v2.</td></tr>';
      return;
    }

    var sevSel = document.getElementById("vsp-ds-filter-severity");
    var toolSel = document.getElementById("vsp-ds-filter-tool");
    var searchInp = document.getElementById("vsp-ds-filter-search");

    var sevVal = sevSel ? sevSel.value : "ALL";
    var toolVal = toolSel ? toolSel.value : "ALL";
    var q = searchInp ? (searchInp.value || "").toLowerCase() : "";

    var filtered = [];
    for (var i = 0; i < ALL_ITEMS.length; i++) {
      var it = ALL_ITEMS[i] || {};
      var sev = (it.severity || "").toString().toUpperCase();
      var tool = (it.tool || "").toString();
      var rule = (it.rule || "").toString();
      var file = (it.file || it.path || "").toString();

      if (sevVal !== "ALL" && sev !== sevVal) continue;
      if (toolVal !== "ALL" && tool !== toolVal) continue;

      if (q) {
        var hay = (rule + " " + file).toLowerCase();
        if (hay.indexOf(q) === -1) continue;
      }

      filtered.push(it);
    }

    if (!filtered.length) {
      tbody.innerHTML = '<tr><td colspan="6" class="vsp-table-empty">Không có findings nào khớp bộ lọc.</td></tr>';
      return;
    }

    var html = "";
    for (var j = 0; j < filtered.length; j++) {
      var f = filtered[j] || {};
      var idx = j + 1;
      var sev2 = f.severity || "";
      var tool2 = f.tool || "";
      var rule2 = f.rule || "";
      var file2 = f.file || f.path || "";
      var line2 = f.line != null ? f.line : "";

      html += '<tr>' +
        '<td>' + idx + '</td>' +
        '<td><span class="' + severityClass(sev2) + '">' + severityLabel(sev2) + '</span></td>' +
        '<td>' + tool2 + '</td>' +
        '<td title="' + rule2 + '">' + rule2 + '</td>' +
        '<td class="vsp-col-filename" title="' + file2 + '">' + file2 + '</td>' +
        '<td>' + line2 + '</td>' +
      '</tr>';
    }

    tbody.innerHTML = html;
  }

  function initFilters(items) {
    var toolSel = document.getElementById("vsp-ds-filter-tool");
    if (!toolSel) return;

    var toolsMap = {};
    for (var i = 0; i < items.length; i++) {
      var t = (items[i] && items[i].tool) || "";
      if (!t) continue;
      toolsMap[t] = true;
    }

    var tools = Object.keys(toolsMap).sort();
    var html = '<option value="ALL">Tất cả tool</option>';
    for (var j = 0; j < tools.length; j++) {
      html += '<option value="' + tools[j] + '">' + tools[j] + '</option>';
    }
    toolSel.innerHTML = html;
  }

  function loadDatasource() {
    var tbody = document.getElementById("vsp-ds-tbody");
    if (tbody) {
      tbody.innerHTML = '<tr><td colspan="6" class="vsp-table-empty">Đang tải unified findings...</td></tr>';
    }

    fetch(API_URL, { cache: "no-store" })
      .then(function (res) { return res.json(); })
      .then(function (data) {
        console.log("[VSP_DS_TAB_V2] datasource_v2 loaded.", data);
        var items = (data && data.items) || (data && data.data) || [];
        ALL_ITEMS = items || [];
        initFilters(ALL_ITEMS);
        applyFilters();
      })
      .catch(function (err) {
        console.error("[VSP_DS_TAB_V2] Failed to load datasource_v2:", err);
        if (tbody) {
          tbody.innerHTML = '<tr><td colspan="6" class="vsp-table-empty">Lỗi tải datasource_v2.</td></tr>';
        }
      });
  }

  function hydratePane() {
    var pane = document.getElementById("vsp-tab-datasource");
    if (!pane) {
      console.warn("[VSP_DS_TAB_V2] Không thấy #vsp-tab-datasource");
      return;
    }

    pane.innerHTML =
      '<div class="vsp-section-header">' +
        '<div>' +
          '<h2 class="vsp-section-title">Data Source</h2>' +
          '<p class="vsp-section-subtitle">Bảng unified findings (tối đa 500 dòng, từ datasource_v2)</p>' +
        '</div>' +
        '<div class="vsp-section-actions">' +
          '<button class="vsp-btn" id="vsp-ds-refresh-btn">Refresh</button>' +
        '</div>' +
      '</div>' +
      '<div class="vsp-card">' +
        '<div class="vsp-ds-filters">' +
          '<div>' +
            '<label for="vsp-ds-filter-severity">Severity</label>' +
            '<select id="vsp-ds-filter-severity" class="vsp-select">' +
              '<option value="ALL">Tất cả mức</option>' +
              '<option value="CRITICAL">CRITICAL</option>' +
              '<option value="HIGH">HIGH</option>' +
              '<option value="MEDIUM">MEDIUM</option>' +
              '<option value="LOW">LOW</option>' +
              '<option value="INFO">INFO</option>' +
              '<option value="TRACE">TRACE</option>' +
            '</select>' +
          '</div>' +
          '<div>' +
            '<label for="vsp-ds-filter-tool">Tool</label>' +
            '<select id="vsp-ds-filter-tool" class="vsp-select">' +
              '<option value="ALL">Đang tải...</option>' +
            '</select>' +
          '</div>' +
          '<div style="flex:1; min-width:200px;">' +
            '<label for="vsp-ds-filter-search">Search</label>' +
            '<input id="vsp-ds-filter-search" class="vsp-input" type="text" placeholder="Tìm theo rule hoặc file...">' +
          '</div>' +
        '</div>' +
        '<div class="vsp-card-table" style="margin-bottom:0;">' +
          '<div class="vsp-table-wrapper">' +
            '<table class="vsp-table vsp-table-datasource">' +
              '<thead>' +
                '<tr>' +
                  '<th style="width:5%;">#</th>' +
                  '<th style="width:10%;">SEV</th>' +
                  '<th style="width:10%;">TOOL</th>' +
                  '<th style="width:25%;">RULE</th>' +
                  '<th style="width:40%;">FILE</th>' +
                  '<th style="width:10%;">LINE</th>' +
                '</tr>' +
              '</thead>' +
              '<tbody id="vsp-ds-tbody">' +
                '<tr><td colspan="6" class="vsp-table-empty">Đang tải unified findings...</td></tr>' +
              '</tbody>' +
            '</table>' +
          '</div>' +
        '</div>' +
      '</div>';

    var btn = document.getElementById("vsp-ds-refresh-btn");
    if (btn) {
      btn.addEventListener("click", function () {
        loadDatasource();
      });
    }

    var sevSel = document.getElementById("vsp-ds-filter-severity");
    var toolSel = document.getElementById("vsp-ds-filter-tool");
    var searchInp = document.getElementById("vsp-ds-filter-search");

    if (sevSel) sevSel.addEventListener("change", applyFilters);
    if (toolSel) toolSel.addEventListener("change", applyFilters);
    if (searchInp) searchInp.addEventListener("input", function () {
      // debounce nhẹ
      clearTimeout(searchInp._vspTimer);
      searchInp._vspTimer = setTimeout(applyFilters, 150);
    });

    loadDatasource();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", hydratePane);
  } else {
    hydratePane();
  }
})();
JS

# --------------------------------------------------
# 4) Settings tab – V2 (card + JSON pretty)
# --------------------------------------------------
backup_if_exists "$JS_DIR/vsp_settings_tab_simple_v1.js"
cat > "$JS_DIR/vsp_settings_tab_simple_v1.js" << 'JS'
(function () {
  var API_URL = "/api/vsp/settings_ui_v1";

  function hydratePane() {
    var pane = document.getElementById("vsp-tab-settings");
    if (!pane) {
      console.warn("[VSP_SETTINGS_TAB_V2] Không thấy #vsp-tab-settings");
      return;
    }

    pane.innerHTML =
      '<div class="vsp-section-header">' +
        '<div>' +
          '<h2 class="vsp-section-title">Settings</h2>' +
          '<p class="vsp-section-subtitle">Cấu hình SECURITY_BUNDLE (settings_ui_v1)</p>' +
        '</div>' +
      '</div>' +
      '<div class="vsp-card">' +
        '<pre id="vsp-settings-pre">{\n  "ok": false,\n  "settings": {}\n}</pre>' +
      '</div>';

    var pre = document.getElementById("vsp-settings-pre");
    if (!pre) return;

    fetch(API_URL, { cache: "no-store" })
      .then(function (res) { return res.json(); })
      .then(function (data) {
        console.log("[VSP_SETTINGS_TAB_V2] settings_ui_v1 loaded.", data);
        try {
          var pretty = JSON.stringify(data, null, 2);
          pre.textContent = pretty;
        } catch (e) {
          pre.textContent = "Lỗi format JSON settings_ui_v1.";
        }
      })
      .catch(function (err) {
        console.error("[VSP_SETTINGS_TAB_V2] Failed to load settings_ui_v1:", err);
        pre.textContent = "Lỗi gọi API settings_ui_v1.";
      });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", hydratePane);
  } else {
    hydratePane();
  }
})();
JS

# --------------------------------------------------
# 5) Rules tab – V2 (card + JSON pretty)
# --------------------------------------------------
backup_if_exists "$JS_DIR/vsp_rules_tab_simple_v1.js"
cat > "$JS_DIR/vsp_rules_tab_simple_v1.js" << 'JS'
(function () {
  var API_URL = "/api/vsp/rule_overrides_ui_v1";

  function hydratePane() {
    var pane = document.getElementById("vsp-tab-rules");
    if (!pane) {
      console.warn("[VSP_RULES_TAB_V2] Không thấy #vsp-tab-rules");
      return;
    }

    pane.innerHTML =
      '<div class="vsp-section-header">' +
        '<div>' +
          '<h2 class="vsp-section-title">Rule Overrides</h2>' +
          '<p class="vsp-section-subtitle">Mapping / override rule (rule_overrides_ui_v1)</p>' +
        '</div>' +
      '</div>' +
      '<div class="vsp-card">' +
        '<pre id="vsp-rules-pre">{\n  "ok": false,\n  "items": []\n}</pre>' +
      '</div>';

    var pre = document.getElementById("vsp-rules-pre");
    if (!pre) return;

    fetch(API_URL, { cache: "no-store" })
      .then(function (res) { return res.json(); })
      .then(function (data) {
        console.log("[VSP_RULES_TAB_V2] rule_overrides_ui_v1 loaded.", data);
        try {
          var pretty = JSON.stringify(data, null, 2);
          pre.textContent = pretty;
        } catch (e) {
          pre.textContent = "Lỗi format JSON rule_overrides_ui_v1.";
        }
      })
      .catch(function (err) {
        console.error("[VSP_RULES_TAB_V2] Failed to load rule_overrides_ui_v1:", err);
        pre.textContent = "Lỗi gọi API rule_overrides_ui_v1.";
      });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", hydratePane);
  } else {
    hydratePane();
  }
})();
JS

echo "[V2_UI] Hoàn tất patch VSP UI V2."
