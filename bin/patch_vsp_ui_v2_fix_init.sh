#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS_DIR="$ROOT/static/js"

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    local b="${f}.bak_v2_init_$(date +%Y%m%d_%H%M%S)"
    cp "$f" "$b"
    echo "[V2_INIT] Backup $f -> $b"
  fi
}

# ---------------- Runs & Reports ----------------
backup "$JS_DIR/vsp_runs_tab_simple_v2.js"
cat > "$JS_DIR/vsp_runs_tab_simple_v2.js" << 'JS'
(function () {
  var API_URL = "/api/vsp/runs_index_v3?limit=40";
  var hydrated = false;

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
    if (hydrated) return;
    var pane = document.getElementById("vsp-tab-runs");
    if (!pane) return;

    hydrated = true;

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
    if (btn) btn.addEventListener("click", loadRuns);

    loadRuns();
  }

  window.vspInitRunsTab = hydratePane;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", hydratePane);
  } else {
    hydratePane();
  }
})();
JS

# ---------------- Data Source ----------------
backup "$JS_DIR/vsp_datasource_tab_simple_v2.js"
cat > "$JS_DIR/vsp_datasource_tab_simple_v2.js" << 'JS'
(function () {
  var API_URL = "/api/vsp/datasource_v2?limit=500";
  var ALL_ITEMS = [];
  var hydrated = false;

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
    if (hydrated) return;
    var pane = document.getElementById("vsp-tab-datasource");
    if (!pane) return;

    hydrated = true;

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
    if (btn) btn.addEventListener("click", loadDatasource);

    var sevSel = document.getElementById("vsp-ds-filter-severity");
    var toolSel = document.getElementById("vsp-ds-filter-tool");
    var searchInp = document.getElementById("vsp-ds-filter-search");

    if (sevSel) sevSel.addEventListener("change", applyFilters);
    if (toolSel) toolSel.addEventListener("change", applyFilters);
    if (searchInp) {
      searchInp.addEventListener("input", function () {
        clearTimeout(searchInp._vspTimer);
        searchInp._vspTimer = setTimeout(applyFilters, 150);
      });
    }

    loadDatasource();
  }

  window.vspInitDatasourceTab = hydratePane;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", hydratePane);
  } else {
    hydratePane();
  }
})();
JS

# ---------------- Settings ----------------
backup "$JS_DIR/vsp_settings_tab_simple_v1.js"
cat > "$JS_DIR/vsp_settings_tab_simple_v1.js" << 'JS'
(function () {
  var API_URL = "/api/vsp/settings_ui_v1";
  var hydrated = false;

  function hydratePane() {
    if (hydrated) return;
    var pane = document.getElementById("vsp-tab-settings");
    if (!pane) return;

    hydrated = true;

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
          pre.textContent = JSON.stringify(data, null, 2);
        } catch (e) {
          pre.textContent = "Lỗi format JSON settings_ui_v1.";
        }
      })
      .catch(function (err) {
        console.error("[VSP_SETTINGS_TAB_V2] Failed to load settings_ui_v1:", err);
        pre.textContent = "Lỗi gọi API settings_ui_v1.";
      });
  }

  window.vspInitSettingsTab = hydratePane;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", hydratePane);
  } else {
    hydratePane();
  }
})();
JS

# ---------------- Rules ----------------
backup "$JS_DIR/vsp_rules_tab_simple_v1.js"
cat > "$JS_DIR/vsp_rules_tab_simple_v1.js" << 'JS'
(function () {
  var API_URL = "/api/vsp/rule_overrides_ui_v1";
  var hydrated = false;

  function hydratePane() {
    if (hydrated) return;
    var pane = document.getElementById("vsp-tab-rules");
    if (!pane) return;

    hydrated = true;

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
          pre.textContent = JSON.stringify(data, null, 2);
        } catch (e) {
          pre.textContent = "Lỗi format JSON rule_overrides_ui_v1.";
        }
      })
      .catch(function (err) {
        console.error("[VSP_RULES_TAB_V2] Failed to load rule_overrides_ui_v1:", err);
        pre.textContent = "Lỗi gọi API rule_overrides_ui_v1.";
      });
  }

  window.vspInitRulesTab = hydratePane;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", hydratePane);
  } else {
    hydratePane();
  }
})();
JS

echo "[V2_INIT] Done patch init/hydrate for 4 tabs."
