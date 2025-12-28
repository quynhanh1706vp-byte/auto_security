// ======================================================================
// VSP_PATCH_5TABS_V1
// - Fix TOP IMPACTED CWE KPI (Dashboard)
// - Bind TAB 2: Runs & Reports (KPI + Run history table)
// - Bind TAB 3: Data Source (table + 2 chart)
//
// YÊU CẦU:
//   Dashboard:
//     <div data-vsp-kpi-top-cwe>...</div>
//
//   Runs tab:
//     KPI: data-vsp-runs-total, data-vsp-runs-last10,
//          data-vsp-runs-avg, data-vsp-runs-tools-per-run
//     Table: <tbody data-vsp-runs-tbody>...</tbody>
//
//   Data Source tab:
//     Table: <tbody data-vsp-ds-tbody>...</tbody>
//     Charts: <canvas id="vsp-ds-severity-donut">, <canvas id="vsp-ds-topcwe">
// ======================================================================

(function () {
  "use strict";

  function qs(sel) { return document.querySelector(sel); }

// ----------------------------------------------------------------------
// 1) DASHBOARD – TOP IMPACTED CWE
// ----------------------------------------------------------------------
  function vspPatchDashboardTopCwe() {
    var el = qs("[data-vsp-kpi-top-cwe]");
    if (!el) return;

    fetch("/api/vsp/dashboard_v3")
      .then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.json();
      })
      .then(function (dash) {
        var hiId = null;
        if (Array.isArray(dash.top_cwe) &&
            dash.top_cwe.length &&
            typeof dash.top_cwe[0].id === "string") {
          hiId = dash.top_cwe[0].id;
        } else if (typeof dash.highest_impacted_cwe === "string") {
          hiId = dash.highest_impacted_cwe;
        } else if (dash.highest_impacted_cwe &&
                   typeof dash.highest_impacted_cwe.id === "string") {
          hiId = dash.highest_impacted_cwe.id;
        }
        el.textContent = hiId || "–";
        console.log("[VSP_PATCH][DASH] Top impacted CWE =", hiId);
      })
      .catch(function (err) {
        console.error("[VSP_PATCH][DASH] Error patching top CWE:", err);
      });
  }

// ----------------------------------------------------------------------
// 2) TAB 2 – RUNS & REPORTS
// ----------------------------------------------------------------------
  function vspPatchRunsTab() {
    var tbody = qs("[data-vsp-runs-tbody]");
    if (!tbody) {
      // không nằm ở tab Runs thì thôi
      return;
    }

    function formatDate(value) {
      if (!value) return "–";
      try {
        var d = new Date(value);
        if (isNaN(d.getTime())) return String(value);
        return d.toISOString().slice(0, 19).replace("T", " ");
      } catch (e) {
        return String(value);
      }
    }

    fetch("/api/vsp/runs_v3?limit=50")
      .then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.json();
      })
      .then(function (runs) {
        if (!Array.isArray(runs)) {
          console.warn("[VSP_PATCH][RUNS] Response không phải array:", runs);
          return;
        }

        console.log("[VSP_PATCH][RUNS] Loaded runs:", runs.length);

        // KPI cho last 10 runs
        var totalRuns = runs.length;
        var last10 = runs.slice(0, 10);
        var okCount = 0, failCount = 0;
        var totalFindings = 0;
        var totalTools = 0, toolsRuns = 0;

        last10.forEach(function (run) {
          if (run.status === "OK" || run.status === "SUCCESS") okCount++;
          else if (run.status === "FAIL" || run.status === "ERROR") failCount++;

          if (typeof run.total_findings === "number") {
            totalFindings += run.total_findings;
          }
          if (run.by_tool && typeof run.by_tool === "object") {
            totalTools += Object.keys(run.by_tool).length;
            toolsRuns++;
          }
        });

        var avgFindings = last10.length ? Math.round(totalFindings / last10.length) : 0;
        var avgTools    = toolsRuns ? (totalTools / toolsRuns).toFixed(1) : "0.0";

        var elTotal = qs("[data-vsp-runs-total]");
        var elLast  = qs("[data-vsp-runs-last10]");
        var elAvg   = qs("[data-vsp-runs-avg]");
        var elTools = qs("[data-vsp-runs-tools-per-run]");

        if (elTotal) elTotal.textContent = String(totalRuns);
        if (elLast)  elLast.textContent  = okCount + " / " + failCount;
        if (elAvg)   elAvg.textContent   = String(avgFindings);
        if (elTools) elTools.textContent = avgTools;

        // Bảng Run history
        tbody.innerHTML = "";
        if (!runs.length) {
          var trEmpty = document.createElement("tr");
          var tdEmpty = document.createElement("td");
          tdEmpty.colSpan = 13;
          tdEmpty.textContent = "No runs.";
          trEmpty.appendChild(tdEmpty);
          tbody.appendChild(trEmpty);
          return;
        }

        runs.forEach(function (run) {
          var tr = document.createElement("tr");
          function td(text) {
            var cell = document.createElement("td");
            cell.textContent = text;
            return cell;
          }

          var runId   = run.run_id || run.id || "–";
          var ts      = formatDate(run.started_at || run.timestamp || run.ts);
          var profile = run.profile || run.mode || "EXT+";
          var src     = run.src_path || run.root_dir || "–";
          var url     = run.target_url || "–";
          var sev     = run.by_severity || {};
          var crit    = sev.CRITICAL || 0;
          var high    = sev.HIGH || 0;
          var med     = sev.MEDIUM || 0;
          var low     = sev.LOW || 0;
          var info    = sev.INFO || 0;
          var trace   = sev.TRACE || 0;
          var total   = typeof run.total_findings === "number"
                        ? run.total_findings
                        : crit + high + med + low + info + trace;
          var tools   = run.by_tool ? Object.keys(run.by_tool).join(",")
                       : (run.tools || "–");

          tr.appendChild(td(runId));
          tr.appendChild(td(ts));
          tr.appendChild(td(profile));
          tr.appendChild(td(src));
          tr.appendChild(td(url));
          tr.appendChild(td(String(crit)));
          tr.appendChild(td(String(high)));
          tr.appendChild(td(String(med)));
          tr.appendChild(td(String(low)));
          tr.appendChild(td(String(info)));
          tr.appendChild(td(String(trace)));
          tr.appendChild(td(String(total)));
          tr.appendChild(td(tools));

          tbody.appendChild(tr);
        });
      })
      .catch(function (err) {
        console.error("[VSP_PATCH][RUNS] Error loading runs_v3:", err);
      });
  }

// ----------------------------------------------------------------------
// 3) TAB 3 – DATA SOURCE
// ----------------------------------------------------------------------
  function vspPatchDataSourceTab() {
    var tbody = qs("[data-vsp-ds-tbody]");
    if (!tbody) {
      return;
    }

    function renderTable(items) {
      tbody.innerHTML = "";
      if (!Array.isArray(items) || !items.length) {
        var trEmpty = document.createElement("tr");
        var tdEmpty = document.createElement("td");
        tdEmpty.colSpan = 10;
        tdEmpty.textContent = "No findings.";
        trEmpty.appendChild(tdEmpty);
        tbody.appendChild(trEmpty);
        return;
      }

      items.forEach(function (f) {
        var tr = document.createElement("tr");
        function td(text) {
          var cell = document.createElement("td");
          cell.textContent = text;
          return cell;
        }

        tr.appendChild(td(f.severity || "–"));
        tr.appendChild(td(f.tool || "–"));
        tr.appendChild(td(f.file || f.path || "–"));
        tr.appendChild(td(f.line != null ? String(f.line) : "–"));
        tr.appendChild(td(f.rule_id || f.rule || "–"));
        tr.appendChild(td(f.message || "–"));
        tr.appendChild(td(f.cwe || "–"));
        tr.appendChild(td(f.cve || "–"));
        tr.appendChild(td(f.module || "–"));
        tr.appendChild(td(Array.isArray(f.tags) ? f.tags.join(",") : (f.tags || "–")));

        tbody.appendChild(tr);
      });
    }

    function buildSeveritySummary(items) {
      var sev = { CRITICAL:0, HIGH:0, MEDIUM:0, LOW:0, INFO:0, TRACE:0 };
      items.forEach(function (f) {
        var s = (f.severity || "").toUpperCase();
        if (sev.hasOwnProperty(s)) sev[s]++;
      });
      return sev;
    }

    function buildTopCwe(items, limit) {
      var map = {};
      items.forEach(function (f) {
        var c = f.cwe || f.cwe_id;
        if (!c) return;
        map[c] = (map[c] || 0) + 1;
      });
      var arr = Object.keys(map).map(function (id) {
        return { id: id, count: map[id] };
      });
      arr.sort(function (a, b) { return b.count - a.count; });
      return arr.slice(0, limit || 8);
    }

    function renderSeverityDonut(sev) {
      var canvas = qs("#vsp-ds-severity-donut");
      if (!canvas || typeof Chart === "undefined") return;

      var labels = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
      var data   = labels.map(function (k) { return sev[k] || 0; });

      new Chart(canvas.getContext("2d"), {
        type: "doughnut",
        data: {
          labels: labels,
          datasets: [{ data: data }]
        },
        options: {
          plugins: { legend: { display: true } }
        }
      });
    }

    function renderTopCweBar(topCwe) {
      var canvas = qs("#vsp-ds-topcwe");
      if (!canvas || typeof Chart === "undefined") return;

      var labels = topCwe.map(function (c) { return c.id; });
      var counts = topCwe.map(function (c) { return c.count; });

      new Chart(canvas.getContext("2d"), {
        type: "bar",
        data: {
          labels: labels,
          datasets: [{ data: counts }]
        },
        options: {
          indexAxis: "y",
          plugins: { legend: { display: false } }
        }
      });
    }

    fetch("/api/vsp/datasource_v2?limit=500")
      .then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.json();
      })
      .then(function (data) {
        var items = Array.isArray(data.items) ? data.items : [];
        console.log("[VSP_PATCH][DS] Loaded datasource_v2 items:", items.length);
        renderTable(items);

        var sev = buildSeveritySummary(items);
        renderSeverityDonut(sev);

        var topCwe = buildTopCwe(items, 8);
        renderTopCweBar(topCwe);
      })
      .catch(function (err) {
        console.error("[VSP_PATCH][DS] Error loading datasource_v2:", err);
      });
  }

// ----------------------------------------------------------------------
// INIT
// ----------------------------------------------------------------------
  document.addEventListener("DOMContentLoaded", function () {
    try {
      vspPatchDashboardTopCwe();
      vspPatchRunsTab();
      vspPatchDataSourceTab();
    } catch (err) {
      console.error("[VSP_PATCH] Init error:", err);
    }
  });

})();
