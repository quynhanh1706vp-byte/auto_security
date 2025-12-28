#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$ROOT/static/js/vsp_console_patch_v1.js"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy $JS"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp "$JS" "${JS}.bak_tabs_api_${TS}"
echo "[BACKUP] $JS -> ${JS}.bak_tabs_api_${TS}"

cat >> "$JS" << 'JS_EOF'

// [VSP_TABS_API_V1]
(function () {
  "use strict";
  var LOG_DS = "[VSP_DS_API]";
  var LOG_SET = "[VSP_SETTINGS_API]";
  var LOG_RULE = "[VSP_RULES_API]";

  function logDs() {
    if (console && console.log) {
      var args = Array.prototype.slice.call(arguments);
      args.unshift(LOG_DS);
      console.log.apply(console, args);
    }
  }
  function logSet() {
    if (console && console.log) {
      var args = Array.prototype.slice.call(arguments);
      args.unshift(LOG_SET);
      console.log.apply(console, args);
    }
  }
  function logRule() {
    if (console && console.log) {
      var args = Array.prototype.slice.call(arguments);
      args.unshift(LOG_RULE);
      console.log.apply(console, args);
    }
  }

  // ---- Data Source /api/vsp/datasource_v2 ----
  function initDataSourceApi() {
    var root = document.getElementById("vsp-ds-root");
    if (!root) {
      logDs("No #vsp-ds-root – skip.");
      return;
    }

    var tbody = document.getElementById("vsp-ds-tbody");
    var selSeverity = document.getElementById("vsp-ds-filter-severity");
    var selTool = document.getElementById("vsp-ds-filter-tool");
    var txtSearch = document.getElementById("vsp-ds-filter-text");
    var btnReload = document.getElementById("vsp-ds-reload");
    var btnPrev = document.getElementById("vsp-ds-prev");
    var btnNext = document.getElementById("vsp-ds-next");
    var lblPage = document.getElementById("vsp-ds-page-info");

    if (!tbody) {
      logDs("Missing tbody #vsp-ds-tbody – skip.");
      return;
    }

    var state = {
      page: 1,
      pageSize: 50,
      total: 0,
      severity: "",
      tool: "",
      q: ""
    };

    function buildUrl() {
      var params = new URLSearchParams();
      if (state.severity) params.set("severity", state.severity);
      if (state.tool) params.set("tool", state.tool);
      if (state.q) params.set("q", state.q);
      params.set("limit", String(state.pageSize));
      params.set("page", String(state.page));
      return "/api/vsp/datasource_v2?" + params.toString();
    }

    function render(data) {
      var items = [];
      if (Array.isArray(data)) {
        items = data;
      } else if (data && Array.isArray(data.items)) {
        items = data.items;
        if (typeof data.total === "number") {
          state.total = data.total;
        }
      }

      tbody.innerHTML = "";
      if (!items.length) {
        var tr = document.createElement("tr");
        var td = document.createElement("td");
        td.colSpan = 8;
        td.textContent = "Không có findings nào (filter quá chặt?).";
        tr.appendChild(td);
        tbody.appendChild(tr);
      } else {
        items.forEach(function (it) {
          var tr = document.createElement("tr");
          function td(text) {
            var c = document.createElement("td");
            c.textContent = text == null ? "" : String(text);
            tr.appendChild(c);
          }

          var sev = it.severity_effective || it.severity || "";
          var tool = it.tool || it.source || "";
          var cwe = it.cwe_id || it.cwe || "";
          var rule = it.rule_id || it.rule || it.check_id || "";
          var path = it.path || it.file || "";
          var line = it.line || it.start_line || "";
          var msg = it.message || it.title || "";
          var run = it.run_id || (data && data.run_id) || "";

          td(sev);
          td(tool);
          td(cwe);
          td(rule);
          td(path);
          td(line);
          td(msg);
          td(run);

          tbody.appendChild(tr);
        });
      }

      var pageInfo = "Page " + state.page;
      if (state.total && state.pageSize) {
        var pages = Math.ceil(state.total / state.pageSize);
        pageInfo = "Page " + state.page + " / " + pages + " (" + state.total + " items)";
      }
      if (lblPage) lblPage.textContent = pageInfo;
    }

    function loadData() {
      var url = buildUrl();
      logDs("Loading", url);
      fetch(url)
        .then(function (res) {
          if (!res.ok) throw new Error("HTTP " + res.status);
          return res.json();
        })
        .then(function (data) {
          logDs("Loaded", data);
          render(data);
        })
        .catch(function (err) {
          logDs("Error", err);
          tbody.innerHTML = "";
          var tr = document.createElement("tr");
          var td = document.createElement("td");
          td.colSpan = 8;
          td.textContent = "Error loading datasource_v2: " + err;
          tr.appendChild(td);
          tbody.appendChild(tr);
        });
    }

    function resetPageAndLoad() {
      state.page = 1;
      loadData();
    }

    if (selSeverity) {
      selSeverity.addEventListener("change", function () {
        state.severity = selSeverity.value || "";
        resetPageAndLoad();
      });
    }
    if (selTool) {
      selTool.addEventListener("change", function () {
        state.tool = selTool.value || "";
        resetPageAndLoad();
      });
    }
    if (txtSearch) {
      txtSearch.addEventListener("keyup", function (e) {
        if (e.key === "Enter") {
          state.q = txtSearch.value || "";
          resetPageAndLoad();
        }
      });
    }
    if (btnReload) {
      btnReload.addEventListener("click", function () {
        resetPageAndLoad();
      });
    }
    if (btnPrev) {
      btnPrev.addEventListener("click", function () {
        if (state.page > 1) {
          state.page -= 1;
          loadData();
        }
      });
    }
    if (btnNext) {
      btnNext.addEventListener("click", function () {
        state.page += 1;
        loadData();
      });
    }

    resetPageAndLoad();
  }

  // ---- Settings /api/vsp/settings_v1 ----
  function initSettingsApi() {
    var root = document.getElementById("vsp-settings-root");
    if (!root) {
      logSet("No #vsp-settings-root – skip.");
      return;
    }

    var txt = document.getElementById("vsp-settings-json");
    var btnReload = document.getElementById("vsp-settings-reload");
    var btnSave = document.getElementById("vsp-settings-save");
    var status = document.getElementById("vsp-settings-status");

    if (!txt) {
      logSet("Missing #vsp-settings-json – skip.");
      return;
    }

    function showStatus(msg, isErr) {
      if (!status) return;
      status.textContent = msg;
      status.style.color = isErr ? "#f97373" : "rgba(148,163,184,0.9)";
    }

    function reloadSettings() {
      showStatus("Loading settings_v1 ...");
      fetch("/api/vsp/settings_v1")
        .then(function (res) {
          if (!res.ok) throw new Error("HTTP " + res.status);
          return res.json();
        })
        .then(function (data) {
          txt.value = JSON.stringify(data, null, 2);
          showStatus("Loaded settings_v1.");
          logSet("Loaded", data);
        })
        .catch(function (err) {
          logSet("Error", err);
          showStatus("Error loading settings_v1: " + err, true);
        });
    }

    function saveSettings() {
      var raw = txt.value;
      var parsed;
      try {
        parsed = JSON.parse(raw);
      } catch (e) {
        showStatus("JSON không hợp lệ: " + e.message, true);
        return;
      }
      showStatus("Saving settings_v1 ...");
      fetch("/api/vsp/settings_v1", {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify(parsed)
      })
        .then(function (res) {
          if (!res.ok) throw new Error("HTTP " + res.status);
          return res.json();
        })
        .then(function (data) {
          showStatus("Saved settings_v1.");
          logSet("Saved", data);
        })
        .catch(function (err) {
          logSet("Save error", err);
          showStatus("Error saving settings_v1: " + err, true);
        });
    }

    if (btnReload) btnReload.addEventListener("click", reloadSettings);
    if (btnSave) btnSave.addEventListener("click", saveSettings);

    // load lần đầu
    reloadSettings();
  }

  // ---- Rule Overrides /api/vsp/rule_overrides_v1 ----
  function initRulesApi() {
    var root = document.getElementById("vsp-rules-root");
    if (!root) {
      logRule("No #vsp-rules-root – skip.");
      return;
    }

    var txt = document.getElementById("vsp-rules-json");
    var tbody = document.getElementById("vsp-rules-tbody");
    var btnReload = document.getElementById("vsp-rules-reload");
    var btnSave = document.getElementById("vsp-rules-save");
    var status = document.getElementById("vsp-rules-status");

    if (!txt || !tbody) {
      logRule("Missing textarea or tbody – skip.");
      return;
    }

    function showStatus(msg, isErr) {
      if (!status) return;
      status.textContent = msg;
      status.style.color = isErr ? "#f97373" : "rgba(148,163,184,0.9)";
    }

    function renderTable(data) {
      var list = [];
      if (Array.isArray(data)) {
        list = data;
      } else if (data && Array.isArray(data.items)) {
        list = data.items;
      }

      tbody.innerHTML = "";
      if (!list.length) {
        var tr = document.createElement("tr");
        var td = document.createElement("td");
        td.colSpan = 5;
        td.textContent = "Không có rule override nào.";
        tr.appendChild(td);
        tbody.appendChild(tr);
        return;
      }

      list.forEach(function (it) {
        var tr = document.createElement("tr");
        function td(text) {
          var c = document.createElement("td");
          c.textContent = text == null ? "" : String(text);
          tr.appendChild(c);
        }
        td(it.id || it.rule_id || "");
        td(it.tool || "");
        td(it.pattern || "");
        td(it.severity_effective || it.severity || "");
        td(it.reason || "");
        tbody.appendChild(tr);
      });
    }

    function reloadRules() {
      showStatus("Loading rule_overrides_v1 ...");
      fetch("/api/vsp/rule_overrides_v1")
        .then(function (res) {
          if (!res.ok) throw new Error("HTTP " + res.status);
          return res.json();
        })
        .then(function (data) {
          txt.value = JSON.stringify(data, null, 2);
          renderTable(data);
          showStatus("Loaded rule_overrides_v1.");
          logRule("Loaded", data);
        })
        .catch(function (err) {
          logRule("Error", err);
          showStatus("Error loading rule_overrides_v1: " + err, true);
        });
    }

    function saveRules() {
      var raw = txt.value;
      var parsed;
      try {
        parsed = JSON.parse(raw);
      } catch (e) {
        showStatus("JSON không hợp lệ: " + e.message, true);
        return;
      }
      showStatus("Saving rule_overrides_v1 ...");
      fetch("/api/vsp/rule_overrides_v1", {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify(parsed)
      })
        .then(function (res) {
          if (!res.ok) throw new Error("HTTP " + res.status);
          return res.json();
        })
        .then(function (data) {
          showStatus("Saved rule_overrides_v1.");
          renderTable(data);
          logRule("Saved", data);
        })
        .catch(function (err) {
          logRule("Save error", err);
          showStatus("Error saving rule_overrides_v1: " + err, true);
        });
    }

    if (btnReload) btnReload.addEventListener("click", reloadRules);
    if (btnSave) btnSave.addEventListener("click", saveRules);

    reloadRules();
  }

  function runAll() {
    initDataSourceApi();
    initSettingsApi();
    initRulesApi();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", runAll);
  } else {
    runAll();
  }
})();
JS_EOF

echo "[OK] Đã append API handlers cho DataSource / Settings / Rules vào $JS"
