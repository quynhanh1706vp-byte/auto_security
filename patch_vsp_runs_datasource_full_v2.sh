#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"

echo "[PATCH] Overwrite vsp_runs_v1.js & vsp_datasource_filters_v2.js dùng data thật"

############################################
# 1) static/js/vsp_runs_v1.js
############################################
cat > "$ROOT/static/js/vsp_runs_v1.js" << 'JS_RUNS'
"use strict";

/**
 * VSP_RUNS_TAB_v2
 * - Dùng /api/vsp/runs_index_v3
 * - Bind KPI row + bảng Run history trên TAB 2.
 */

(function() {
  var LOG_PREFIX = "[VSP_RUNS_TAB]";
  function log() {
    if (window.console && console.log) {
      var args = Array.prototype.slice.call(arguments);
      args.unshift(LOG_PREFIX);
      console.log.apply(console, args);
    }
  }

  function safeFetchJson(url) {
    return fetch(url, { credentials: "same-origin" })
      .then(function(resp) {
        if (!resp.ok) throw new Error("HTTP " + resp.status);
        return resp.json();
      });
  }

  function deriveRunsArray(payload) {
    if (!payload) return [];
    if (Array.isArray(payload)) return payload;
    if (Array.isArray(payload.runs)) return payload.runs;
    if (Array.isArray(payload.items)) return payload.items;
    if (Array.isArray(payload.data)) return payload.data;
    return [];
  }

  function parseTs(run) {
    var t = run.timestamp || run.started_at || run.time || "";
    if (!t) return 0;
    var d = new Date(t);
    var v = d.getTime();
    if (!v || isNaN(v)) return 0;
    return v;
  }

  function sortRuns(runs) {
    runs.sort(function(a, b) {
      return parseTs(b) - parseTs(a);
    });
    return runs;
  }

  function computeKpis(runs) {
    var totalRuns = runs.length;
    var last10 = runs.slice(0, 10);

    var okCount = 0;
    var failCount = 0;

    last10.forEach(function(r) {
      var ok = false;
      if (r.ok === true) ok = true;
      if (typeof r.status === "string" && r.status.toLowerCase() === "ok") ok = true;
      if (typeof r.status === "string" && r.status.toLowerCase() === "success") ok = true;
      if (ok) okCount += 1;
      else failCount += 1;
    });

    var totalFindingsAll = 0;
    var totalRunsWithFindings = 0;
    var totalToolsAll = 0;

    runs.forEach(function(r) {
      var tf = r.total_findings;
      if (typeof tf === "number") {
        totalFindingsAll += tf;
        totalRunsWithFindings += 1;
      }
      var toolCount = 0;
      if (r.by_tool && typeof r.by_tool === "object") {
        toolCount = Object.keys(r.by_tool).length;
      } else if (Array.isArray(r.tools)) {
        toolCount = r.tools.length;
      } else if (typeof r.tools_enabled_count === "number") {
        toolCount = r.tools_enabled_count;
      }
      totalToolsAll += toolCount;
    });

    var avgFindings = 0;
    if (totalRunsWithFindings > 0) {
      avgFindings = totalFindingsAll / totalRunsWithFindings;
    }

    var avgTools = 0;
    if (totalRuns > 0) {
      avgTools = totalToolsAll / totalRuns;
    }

    return {
      totalRuns: totalRuns,
      last10Ok: okCount,
      last10Fail: failCount,
      avgFindings: avgFindings,
      avgTools: avgTools
    };
  }

  function renderKpis(kpi) {
    var cards = document.querySelectorAll("#tab-runs .runs-kpi-row .vsp-card");
    if (!cards.length) {
      log("Không tìm thấy KPI cards trên TAB 2");
      return;
    }

    // 0: Total runs
    if (cards[0]) {
      var v0 = cards[0].querySelector(".kpi-value");
      var t0 = cards[0].querySelector(".kpi-trend");
      if (v0) v0.textContent = kpi.totalRuns || 0;
      if (t0) t0.textContent = "All time";
    }

    // 1: Last 10 runs
    if (cards[1]) {
      var v1 = cards[1].querySelector(".kpi-value");
      var t1 = cards[1].querySelector(".kpi-trend");
      if (v1) v1.textContent = (kpi.last10Ok + kpi.last10Fail) || 0;
      if (t1) t1.textContent = "Success: " + kpi.last10Ok + " · Failed: " + kpi.last10Fail;
    }

    // 2: Avg findings / run
    if (cards[2]) {
      var v2 = cards[2].querySelector(".kpi-value");
      var t2 = cards[2].querySelector(".kpi-trend");
      if (v2) v2.textContent = kpi.avgFindings ? Math.round(kpi.avgFindings) : 0;
      if (t2) t2.textContent = "Weighted by severity";
    }

    // 3: Tools enabled / run
    if (cards[3]) {
      var v3 = cards[3].querySelector(".kpi-value");
      var t3 = cards[3].querySelector(".kpi-trend");
      if (v3) {
        var avgTools = kpi.avgTools ? (Math.round(kpi.avgTools * 10) / 10) : 0;
        v3.textContent = avgTools + " / 7";
      }
      if (t3) t3.textContent = "Semgrep · Gitleaks · ...";
    }
  }

  function renderRunsTable(runs) {
    var tbody = document.getElementById("vsp-runs-tbody");
    if (!tbody) {
      log("Không tìm thấy tbody#vsp-runs-tbody – bỏ qua render bảng.");
      return;
    }

    tbody.innerHTML = "";

    runs.forEach(function(r, idx) {
      var tr = document.createElement("tr");

      function td(text) {
        var el = document.createElement("td");
        el.textContent = (text === null || text === undefined) ? "" : String(text);
        return el;
      }

      var sev = r.by_severity || r.severity || {};
      var crit  = sev.CRITICAL || sev.critical || 0;
      var high  = sev.HIGH     || sev.high     || 0;
      var med   = sev.MEDIUM   || sev.medium   || 0;
      var low   = sev.LOW      || sev.low      || 0;
      var info  = sev.INFO     || sev.info     || 0;
      var trace = sev.TRACE    || sev.trace    || 0;

      tr.appendChild(td(r.run_id || r.id || (idx + 1)));
      tr.appendChild(td(r.timestamp || r.started_at || ""));
      tr.appendChild(td(r.profile || ""));
      tr.appendChild(td(r.src_path || r.source || ""));
      tr.appendChild(td(r.target_url || r.url || ""));
      tr.appendChild(td(crit));
      tr.appendChild(td(high));
      tr.appendChild(td(med));
      tr.appendChild(td(low));
      tr.appendChild(td(info));
      tr.appendChild(td(trace));
      tr.appendChild(td(r.total_findings || r.total || ""));
      tr.appendChild(td(r.tools_summary || r.tools && r.tools.join(",") || "Semgrep,Gitleaks,..."));
      tr.appendChild(td("HTML · PDF · CSV"));

      tbody.appendChild(tr);
    });
  }

  function initRunsTab() {
    var tab = document.getElementById("tab-runs");
    if (!tab) return;

    safeFetchJson("/api/vsp/runs_index_v3")
      .then(function(payload) {
        var runs = deriveRunsArray(payload);
        log("Loaded " + runs.length + " runs từ runs_index_v3");
        if (!runs.length) {
          renderRunsTable([]);
          renderKpis({
            totalRuns: 0,
            last10Ok: 0,
            last10Fail: 0,
            avgFindings: 0,
            avgTools: 0
          });
          return;
        }
        sortRuns(runs);
        var kpi = computeKpis(runs);
        renderKpis(kpi);
        renderRunsTable(runs);
      })
      .catch(function(err) {
        console.error(LOG_PREFIX, "Lỗi load runs_index_v3", err);
      });
  }

  document.addEventListener("DOMContentLoaded", initRunsTab);
})();
JS_RUNS

############################################
# 2) static/js/vsp_datasource_filters_v2.js
############################################
cat > "$ROOT/static/js/vsp_datasource_filters_v2.js" << 'JS_DS'
"use strict";

/**
 * VSP_DATASOURCE_TAB_v2
 * - Dùng /api/vsp/datasource_v2
 * - Đổ bảng Unified findings + chart severity / CWE.
 */

(function() {
  var LOG_PREFIX = "[VSP_DS_TAB]";

  function log() {
    if (window.console && console.log) {
      var args = Array.prototype.slice.call(arguments);
      args.unshift(LOG_PREFIX);
      console.log.apply(console, args);
    }
  }

  function safeFetchJson(url) {
    return fetch(url, { credentials: "same-origin" })
      .then(function(resp) {
        if (!resp.ok) throw new Error("HTTP " + resp.status);
        return resp.json();
      });
  }

  function deriveItems(payload) {
    if (!payload) return [];
    if (Array.isArray(payload)) return payload;
    if (Array.isArray(payload.items)) return payload.items;
    if (Array.isArray(payload.findings)) return payload.findings;
    return [];
  }

  function renderTable(items) {
    var tbody = document.querySelector("#tab-data .vsp-table tbody");
    if (!tbody) {
      log("Không tìm thấy tbody bảng unified findings");
      return;
    }
    tbody.innerHTML = "";

    items.forEach(function(it) {
      var tr = document.createElement("tr");

      function td(text) {
        var el = document.createElement("td");
        el.textContent = (text === null || text === undefined) ? "" : String(text);
        return el;
      }

      tr.appendChild(td(it.severity || it.severity_effective || ""));
      tr.appendChild(td(it.tool || ""));
      tr.appendChild(td(it.file || it.path || ""));
      tr.appendChild(td(it.line || ""));
      tr.appendChild(td(it.rule_id || ""));
      tr.appendChild(td(it.message || ""));
      tr.appendChild(td(it.cwe || ""));
      tr.appendChild(td(it.cve || ""));
      tr.appendChild(td(it.module || it.src_path || ""));
      tr.appendChild(td(it.fix || ""));
      tr.appendChild(td(Array.isArray(it.tags) ? it.tags.join(",") : (it.tags || "")));

      tbody.appendChild(tr);
    });
  }

  function aggregateForCharts(items) {
    var sev = { CRITICAL:0, HIGH:0, MEDIUM:0, LOW:0, INFO:0, TRACE:0 };
    var cweCount = {};

    items.forEach(function(it) {
      var s = (it.severity_effective || it.severity || "").toUpperCase();
      if (sev.hasOwnProperty(s)) {
        sev[s] += 1;
      }

      var cwe = it.cwe || "";
      if (cwe) {
        if (!cweCount[cwe]) cweCount[cwe] = 0;
        cweCount[cwe] += 1;
      }
    });

    var cweEntries = Object.keys(cweCount).map(function(k) {
      return { cwe: k, count: cweCount[k] };
    });

    cweEntries.sort(function(a, b) { return b.count - a.count; });
    cweEntries = cweEntries.slice(0, 5);

    return { severity: sev, topCwe: cweEntries };
  }

  function safeCtx(id) {
    if (!window.Chart) return null;
    var el = document.getElementById(id);
    if (!el) return null;
    if (el.getContext) return el.getContext("2d");
    return el;
  }

  function renderCharts(agg) {
    if (!window.Chart) {
      log("Chart.js chưa sẵn, bỏ qua chart");
      return;
    }

    // Severity donut
    (function() {
      var ctx = safeCtx("dataSeverityDonut");
      if (!ctx) return;
      var s = agg.severity;
      new Chart(ctx, {
        type: "doughnut",
        data: {
          labels: ["CRIT","HIGH","MED","LOW","INFO","TRACE"],
          datasets: [{
            data: [
              s.CRITICAL || 0,
              s.HIGH || 0,
              s.MEDIUM || 0,
              s.LOW || 0,
              s.INFO || 0,
              s.TRACE || 0
            ],
            backgroundColor: [
              "#ff1744",
              "#ff6d00",
              "#fbbf24",
              "#22c55e",
              "#38bdf8",
              "#a855f7"
            ],
            borderWidth: 0
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: { position: "bottom" }
          },
          cutout: "65%"
        }
      });
    })();

    // Top CWE chart
    (function() {
      var ctx = safeCtx("dataCWEAndDirs");
      if (!ctx) return;
      var labels = [];
      var counts = [];
      agg.topCwe.forEach(function(e) {
        labels.push(e.cwe);
        counts.push(e.count);
      });
      if (!labels.length) {
        labels = ["N/A"];
        counts = [0];
      }
      new Chart(ctx, {
        type: "bar",
        data: {
          labels: labels,
          datasets: [{
            label: "Findings",
            data: counts,
            backgroundColor: "#22d3ee"
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          scales: {
            x: {
              ticks: { color: "#9ca3af", font: { size: 9 } },
              grid: { display: false }
            },
            y: {
              ticks: { color: "#9ca3af", font: { size: 9 } },
              grid: { color: "rgba(55,65,81,0.4)" }
            }
          },
          plugins: {
            legend: { display: false }
          }
        }
      });
    })();
  }

  function initDataTab() {
    var tab = document.getElementById("tab-data");
    if (!tab) return;

    // Limit có thể chỉnh sau, tạm 500 dòng cho UI.
    safeFetchJson("/api/vsp/datasource_v2?limit=500")
      .then(function(payload) {
        var items = deriveItems(payload);
        log("Loaded " + items.length + " findings từ datasource_v2");
        renderTable(items);
        var agg = aggregateForCharts(items);
        renderCharts(agg);
      })
      .catch(function(err) {
        console.error(LOG_PREFIX, "Lỗi load datasource_v2", err);
      });
  }

  document.addEventListener("DOMContentLoaded", initDataTab);
})();
JS_DS

echo "[PATCH] Done."
