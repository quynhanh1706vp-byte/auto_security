/* =========================================================
 * VSP_TABS_RUNTIME_V2
 * Đẩy data lên:
 *  - Dashboard: Top risk findings + Top noisy paths
 *  - Runs & Reports: Run history
 *  - Data Source: Findings list
 *  - Settings: Raw settings JSON
 *  - Rule Overrides: Placeholder trạng thái overrides
 * Không sửa layout, chỉ bơm data vào các bảng hiện có.
 * ========================================================= */

(function () {
  "use strict";

  function dbg() {
    if (window.console && console.log) {
      console.log.apply(console, arguments);
    }
  }

  function findContainerByHeading(keyword) {
    keyword = (keyword || "").toLowerCase();
    if (!keyword) return null;

    var headings = document.querySelectorAll("h1,h2,h3,h4,h5");
    for (var i = 0; i < headings.length; i++) {
      var h = headings[i];
      var txt = (h.textContent || "").toLowerCase();
      if (txt.indexOf(keyword) !== -1) {
        var container = h.closest("section, article, div") || h.parentElement;
        if (container) return container;
      }
    }
    return null;
  }

  function findTbodyByHeading(keyword) {
    var container = findContainerByHeading(keyword);
    if (!container) return null;
    return container.querySelector("tbody");
  }

  /* 1) Dashboard – TOP RISK FINDINGS (CRITICAL + HIGH) */
  function loadTopRiskFindings() {
    var severities = ["CRITICAL", "HIGH"];
    var promises = [];

    severities.forEach(function (sev) {
      var url = "/api/vsp/datasource_v2?severity=" +
                encodeURIComponent(sev) + "&limit=50";
      dbg("[VSP][TAB] top risks GET", url);
      promises.push(
        fetch(url)
          .then(function (r) { return r.json(); })
          .catch(function (e) {
            console.error("[VSP][TAB] top risks ERR (" + sev + "):", e);
            return null;
          })
      );
    });

    Promise.all(promises).then(function (results) {
      var tbody = findTbodyByHeading("top risk findings");
      if (!tbody) {
        dbg("[VSP][TAB] Không tìm thấy bảng 'Top risk findings'.");
        return;
      }

      var allItems = [];
      results.forEach(function (res) {
        if (!res || res.ok === false || !Array.isArray(res.items)) return;
        allItems = allItems.concat(res.items);
      });

      if (!allItems.length) {
        tbody.innerHTML =
          '<tr><td colspan="4">No CRITICAL/HIGH findings.</td></tr>';
        return;
      }

      var weight = { CRITICAL: 2, HIGH: 1 };
      allItems.sort(function (a, b) {
        var sa = a.severity_effective || a.severity || "HIGH";
        var sb = b.severity_effective || b.severity || "HIGH";
        var wa = weight[sa] || 0;
        var wb = weight[sb] || 0;
        if (wa !== wb) return wb - wa;
        return 0;
      });

      allItems = allItems.slice(0, 10);

      tbody.innerHTML = "";
      allItems.forEach(function (it) {
        var sev  = it.severity_effective || it.severity || "N/A";
        var tool = it.tool || "";
        var loc  = it.file || it.path || "";
        var rule = it.rule_id || it.cwe || "";

        var tr = document.createElement("tr");
        tr.innerHTML =
          "<td>" + sev  + "</td>" +
          "<td>" + tool + "</td>" +
          "<td>" + loc  + "</td>" +
          "<td>" + rule + "</td>";
        tbody.appendChild(tr);
      });
    });
  }

  /* 2) Dashboard – TOP NOISY PATHS (MEDIUM/LOW/INFO/TRACE) */
  function loadTopNoisyPaths() {
    var severities = ["MEDIUM", "LOW", "INFO", "TRACE"];
    var promises = [];

    severities.forEach(function (sev) {
      var url = "/api/vsp/datasource_v2?severity=" +
                encodeURIComponent(sev) + "&limit=200";
      dbg("[VSP][TAB] noisy paths GET", url);
      promises.push(
        fetch(url)
          .then(function (r) { return r.json(); })
          .catch(function (e) {
            console.error("[VSP][TAB] noisy paths ERR (" + sev + "):", e);
            return null;
          })
      );
    });

    Promise.all(promises).then(function (results) {
      var tbody = findTbodyByHeading("top noisy paths");
      if (!tbody) {
        dbg("[VSP][TAB] Không tìm thấy bảng 'Top noisy paths'.");
        return;
      }

      var counts = {};
      results.forEach(function (res) {
        if (!res || res.ok === false || !Array.isArray(res.items)) return;
        res.items.forEach(function (it) {
          var key = it.file || it.path || "";
          if (!key) return;
          counts[key] = (counts[key] || 0) + 1;
        });
      });

      var paths = Object.keys(counts).map(function (path) {
        return { path: path, total: counts[path] };
      });

      if (!paths.length) {
        tbody.innerHTML =
          '<tr><td colspan="3">No noisy paths (MEDIUM/LOW/INFO/TRACE).</td></tr>';
        return;
      }

      paths.sort(function (a, b) { return b.total - a.total; });

      function noiseLevel(total) {
        if (total >= 20) return "HIGH";
        if (total >= 10) return "MEDIUM";
        if (total >= 3)  return "LOW";
        return "MINOR";
      }

      paths = paths.slice(0, 10);

      tbody.innerHTML = "";
      paths.forEach(function (e) {
        var tr = document.createElement("tr");
        tr.innerHTML =
          "<td>" + e.path + "</td>" +
          "<td>" + e.total + "</td>" +
          "<td>" + noiseLevel(e.total) + "</td>";
        tbody.appendChild(tr);
      });
    });
  }

  /* 3) Runs & Reports – RUN HISTORY */
  function loadRunsTab() {
    dbg("[VSP][TAB] Runs & Reports -> /api/vsp/runs_v2");
    fetch("/api/vsp/runs_v2")
      .then(function (r) { return r.json(); })
      .then(function (data) {
        dbg("[VSP][TAB] runs_v2:", data);
        var tbody =
          findTbodyByHeading("run history") ||
          findTbodyByHeading("runs & reports");
        if (!tbody) {
          dbg("[VSP][TAB] Không tìm thấy bảng run history.");
          return;
        }

        if (!data || data.ok === false || !Array.isArray(data.items)) {
          tbody.innerHTML =
            '<tr><td colspan="5">No runs.</td></tr>';
          return;
        }

        tbody.innerHTML = "";
        data.items.forEach(function (row) {
          var tr = document.createElement("tr");
          tr.innerHTML =
            "<td>" + (row.run_id || "–") + "</td>" +
            "<td>" + (row.ts || "–") + "</td>" +
            "<td>" + (row.total_findings || 0) + "</td>" +
            "<td>" + (row.security_score || 0) + "</td>" +
            "<td>" + (row.status || "DONE") + "</td>";
          tbody.appendChild(tr);
        });
      })
      .catch(function (e) {
        console.error("[VSP][TAB] runs_v2 ERR:", e);
      });
  }

  /* 4) Data Source – FINDINGS LIST */
  function loadDataSourceTab() {
    dbg("[VSP][TAB] Data Source -> /api/vsp/datasource_v2");
    fetch("/api/vsp/datasource_v2?limit=100")
      .then(function (r) { return r.json(); })
      .then(function (data) {
        dbg("[VSP][TAB] datasource_v2:", data);
        var tbody = findTbodyByHeading("data source");
        if (!tbody) {
          dbg("[VSP][TAB] Không tìm thấy bảng Data Source.");
          return;
        }

        if (!data || data.ok === false || !Array.isArray(data.items)) {
          tbody.innerHTML =
            '<tr><td colspan="5">No findings.</td></tr>';
          return;
        }

        tbody.innerHTML = "";
        data.items.forEach(function (it) {
          var sev  = it.severity_effective || it.severity || "N/A";
          var tool = it.tool || "";
          var loc  = it.file || it.path || "";
          var rule = it.rule_id || it.cwe || "";
          var msg  = it.message || "";

          var tr = document.createElement("tr");
          tr.innerHTML =
            "<td>" + sev  + "</td>" +
            "<td>" + tool + "</td>" +
            "<td>" + loc  + "</td>" +
            "<td>" + rule + "</td>" +
            "<td>" + msg  + "</td>";
          tbody.appendChild(tr);
        });
      })
      .catch(function (e) {
        console.error("[VSP][TAB] datasource_v2 ERR:", e);
      });
  }

  /* 5) Settings – RAW SETTINGS JSON */
  function loadSettingsTab() {
    dbg("[VSP][TAB] Settings -> /api/vsp/settings_v1");
    fetch("/api/vsp/settings_v1")
      .then(function (r) { return r.json(); })
      .then(function (data) {
        dbg("[VSP][TAB] settings_v1:", data);
        var container = findContainerByHeading("settings");
        if (!container) {
          dbg("[VSP][TAB] Không tìm thấy khu vực Settings.");
          return;
        }
        var pre = container.querySelector("pre, code");
        if (!pre) {
          pre = document.createElement("pre");
          container.appendChild(pre);
        }
        pre.textContent = JSON.stringify(data, null, 2);
      })
      .catch(function (e) {
        console.error("[VSP][TAB] settings_v1 ERR:", e);
      });
  }

  /* 6) Rule Overrides – placeholder */
  function loadOverridesTab() {
    dbg("[VSP][TAB] Rule Overrides – placeholder");
    var container = findContainerByHeading("rule overrides");
    if (!container) return;
    var pre = container.querySelector("pre, code");
    if (!pre) {
      pre = document.createElement("pre");
      container.appendChild(pre);
    }
    pre.textContent =
      "Rule Overrides tab – TODO: /api/vsp/overrides_v1.\n" +
      "Hiện overrides đã áp vào severity_effective trong findings_unified.json.";
  }

  /* Bind nav click (không đụng layout) */
  function bindNavClick(label, handler) {
    var labelLower = label.toLowerCase();
    var navItems = document.querySelectorAll("nav a, nav button, .vsp-nav-item, .nav-link");
    for (var i = 0; i < navItems.length; i++) {
      (function (el) {
        var txt = (el.textContent || "").toLowerCase();
        if (txt.indexOf(labelLower) !== -1) {
          el.addEventListener("click", function () {
            handler();
          });
        }
      })(navItems[i]);
    }
  }

  function init() {
    dbg("[VSP][TAB] tabs runtime init");

    // Dashboard: chạy luôn
    loadTopRiskFindings();
    loadTopNoisyPaths();

    // Các tab khác: load khi click
    bindNavClick("runs & reports", loadRunsTab);
    bindNavClick("history",        loadRunsTab);
    bindNavClick("data source",    loadDataSourceTab);
    bindNavClick("settings",       loadSettingsTab);
    bindNavClick("rule overrides", loadOverridesTab);
  }

  document.addEventListener("DOMContentLoaded", init);
})();
