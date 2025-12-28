/* VSP_P2_TREND_PATH_FORCE_V2 */
/* ---------------------------------------------------------
 * VSP CIO VIEW – DASHBOARD LIVE JS (FULL, NO DELAY)
 * ---------------------------------------------------------
 * - Dashboard:  /api/vsp/dashboard_v3
 * - Trend:      /api/vsp/trend_v1?path=run_gate_summary.json
 * - Runs:       /api/vsp/runs_v2
 * - Top risks:  /api/vsp/datasource_v2 (CRITICAL, HIGH)
 * - Noisy paths:/api/vsp/datasource_v2 (MEDIUM, LOW, INFO, TRACE)
 * --------------------------------------------------------- */

(function () {
  "use strict";

  function qs(sel, root) {
    return (root || document).querySelector(sel);
  }
  function qsa(sel, root) {
    return Array.prototype.slice.call(
      (root || document).querySelectorAll(sel) || []
    );
  }
  function setText(el, v) {
    if (el) el.textContent = v != null ? String(v) : "–";
  }
  function dbg() {
    console.log.apply(console, arguments);
  }

  /* ------------------------------
     DASHBOARD V3
  ------------------------------ */
  function loadDashboardV3() {
    dbg("[VSP] /api/vsp/dashboard_v3 -> load");

    fetch("/api/vsp/dashboard_v3")
      .then(function (r) { return r.json(); })
      .then(function (data) {
        dbg("[VSP] dashboard_v3:", data);

        if (!data || data.ok === false) return;

        // KPI zone
        setText(qs("#vsp-kpi-total"), data.total_findings);
        setText(qs("#vsp-kpi-score"), data.security_score);
        setText(qs("#vsp-kpi-tool"), data.top_risky_tool || "–");
        setText(qs("#vsp-kpi-cwe"), data.top_cwe || "–");
        setText(qs("#vsp-kpi-module"), data.top_module || "–");

        // Severity buckets (6 mức)
        var sev = data.by_severity || {};
        setText(qs("#sev-critical"), sev.CRITICAL || 0);
        setText(qs("#sev-high"),     sev.HIGH     || 0);
        setText(qs("#sev-med"),      sev.MEDIUM   || 0);
        setText(qs("#sev-low"),      sev.LOW      || 0);
        setText(qs("#sev-info"),     sev.INFO     || 0);
        setText(qs("#sev-trace"),    sev.TRACE    || 0);

        // Tool breakdown (nếu HTML có sẵn chỗ để bind)
        var byTool = data.by_tool || {};
        Object.keys(byTool).forEach(function (tool) {
          var el = qs('[data-vsp-tool="' + tool + '"]');
          if (el) setText(el, byTool[tool]);
        });
      })
      .catch(function (err) {
        console.error("[VSP] dashboard_v3 ERR:", err);
      });
  }

  /* ------------------------------
     TREND
  ------------------------------ */
  function loadTrend() {
    dbg("[VSP] /api/vsp/trend_v1?path=run_gate_summary.json -> load");

    fetch("/api/vsp/trend_v1?path=run_gate_summary.json")
      .then(function (r) { return r.json(); })
      .then(function (data) {
        dbg("[VSP] trend_v1:", data);

        var tbody = qs("#vsp-trend-body");
        if (!tbody) return;

        if (!data || !Array.isArray(data.points)) {
          tbody.innerHTML =
            '<tr><td colspan="4">No trend data</td></tr>';
          return;
        }

        tbody.innerHTML = "";
        data.points.forEach(function (p) {
          var tr = document.createElement("tr");
          tr.innerHTML =
            "<td>" + (p.ts || "–") + "</td>" +
            "<td>" + (p.run_id || "–") + "</td>" +
            "<td>" + (p.total_findings || p.total || 0) + "</td>" +
            "<td>" + (p.security_score || 0) + "</td>";
          tbody.appendChild(tr);
        });
      })
      .catch(function (err) {
        console.error("[VSP] trend ERR:", err);
      });
  }

  /* ------------------------------
     RUNS
  ------------------------------ */
  function loadRuns() {
    dbg("[VSP] /api/vsp/runs_v2 -> load");

    fetch("/api/vsp/runs_v2")
      .then(function (r) { return r.json(); })
      .then(function (data) {
        dbg("[VSP] runs_v2:", data);

        var tbody = qs("#vsp-runs-body");
        if (!tbody) return;

        if (!data || !Array.isArray(data.items)) {
          tbody.innerHTML =
            '<tr><td colspan="5">No runs</td></tr>';
          return;
        }

        tbody.innerHTML = "";
        data.items.forEach(function (row) {
          var tr = document.createElement("tr");
          tr.innerHTML =
            "<td>" + (row.ts || "–") + "</td>" +
            "<td>" + (row.run_id || "–") + "</td>" +
            "<td>" + (row.total_findings || 0) + "</td>" +
            "<td>" + (row.security_score || 0) + "</td>" +
            "<td>" + (row.status || "DONE") + "</td>";
          tbody.appendChild(tr);
        });
      })
      .catch(function (err) {
        console.error("[VSP] runs ERR:", err);
      });
  }

  /* ------------------------------
     TOP RISK FINDINGS
     (CRITICAL + HIGH)
  ------------------------------ */
  function loadTopRiskFindings() {
    var severities = ["CRITICAL", "HIGH"];
    var requests = severities.map(function (sev) {
      var url = "/api/vsp/datasource_v2?severity=" + encodeURIComponent(sev) +
                "&limit=50";
      dbg("[VSP] top risks: GET", url);
      return fetch(url)
        .then(function (r) { return r.json(); })
        .catch(function (e) {
          console.error("[VSP] top risks fetch ERR (" + sev + "):", e);
          return null;
        });
    });

    Promise.all(requests).then(function (results) {
      var tbody = qs("#vsp-top-risk-body");
      if (!tbody) {
        console.warn("[VSP] #vsp-top-risk-body not found in DOM");
        return;
      }

      var allItems = [];
      results.forEach(function (res) {
        if (!res || res.ok === false) return;
        if (Array.isArray(res.items)) {
          allItems = allItems.concat(res.items);
        }
      });

      if (!allItems.length) {
        tbody.innerHTML =
          '<tr><td colspan="4">No CRITICAL/HIGH findings.</td></tr>';
        return;
      }

      // Ưu tiên CRITICAL trước HIGH
      var weight = { CRITICAL: 2, HIGH: 1 };
      allItems.sort(function (a, b) {
        var sa = (a.severity_effective || a.severity || "HIGH");
        var sb = (b.severity_effective || b.severity || "HIGH");
        var wa = weight[sa] || 0;
        var wb = weight[sb] || 0;
        if (wa !== wb) return wb - wa;
        return 0;
      });

      // Lấy TOP 10
      allItems = allItems.slice(0, 10);

      tbody.innerHTML = "";
      allItems.forEach(function (it) {
        var sev = it.severity_effective || it.severity || "N/A";
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

  /* ------------------------------
     TOP NOISY PATHS
     (MEDIUM / LOW / INFO / TRACE)
  ------------------------------ */
  function loadTopNoisyPaths() {
    var severities = ["MEDIUM", "LOW", "INFO", "TRACE"];
    var requests = severities.map(function (sev) {
      var url = "/api/vsp/datasource_v2?severity=" + encodeURIComponent(sev) +
                "&limit=200";
      dbg("[VSP] noisy paths: GET", url);
      return fetch(url)
        .then(function (r) { return r.json(); })
        .catch(function (e) {
          console.error("[VSP] noisy paths fetch ERR (" + sev + "):", e);
          return null;
        });
    });

    Promise.all(requests).then(function (results) {
      var tbody = qs("#vsp-noisy-paths-body");
      if (!tbody) {
        console.warn("[VSP] #vsp-noisy-paths-body not found in DOM");
        return;
      }

      var counts = {}; // key = path/file -> total
      results.forEach(function (res) {
        if (!res || res.ok === false) return;
        if (!Array.isArray(res.items)) return;

        res.items.forEach(function (it) {
          var key = it.file || it.path || "";
          if (!key) return;
          if (!counts[key]) counts[key] = 0;
          counts[key] += 1;
        });
      });

      var entries = Object.keys(counts).map(function (path) {
        return { path: path, total: counts[path] };
      });

      if (!entries.length) {
        tbody.innerHTML =
          '<tr><td colspan="3">No noisy paths (MEDIUM/LOW/INFO/TRACE).</td></tr>';
        return;
      }

      // Sort desc theo total
      entries.sort(function (a, b) {
        return b.total - a.total;
      });

      // Helper noise level
      function noiseLevel(total) {
        if (total >= 20) return "HIGH";
        if (total >= 10) return "MEDIUM";
        if (total >= 3)  return "LOW";
        return "MINOR";
      }

      // Lấy TOP 10
      entries = entries.slice(0, 10);

      tbody.innerHTML = "";
      entries.forEach(function (e) {
        var tr = document.createElement("tr");
        tr.innerHTML =
          "<td>" + e.path + "</td>" +
          "<td>" + e.total + "</td>" +
          "<td>" + noiseLevel(e.total) + "</td>";
        tbody.appendChild(tr);
      });
    });
  }

  /* ------------------------------
     INIT
  ------------------------------ */
  document.addEventListener("DOMContentLoaded", function () {
    dbg("[VSP] CIO dashboard init");

    // Load ngay không delay
    loadDashboardV3();
    loadTrend();
    loadRuns();
    loadTopRiskFindings();
    loadTopNoisyPaths();
  });
})();

/**
 * [VSP_DASHBOARD_BIND_V3_FIX]
 * Lớp fix nhẹ:
 * - Gọi /api/vsp/dashboard_v3
 * - Đổ lại 6 bucket severity + Security Score + Top Tool/CWE/Module
 * - Dùng các id:
 *   vsp-kpi-total, vsp-kpi-critical, vsp-kpi-high, vsp-kpi-medium,
 *   vsp-kpi-low, vsp-kpi-info, vsp-kpi-trace,
 *   vsp-kpi-security-score, vsp-kpi-top-tool,
 *   vsp-kpi-top-cwe, vsp-kpi-top-module
 */

(function () {
  const API_URL = "/api/vsp/dashboard_v3";

  function $(id) {
    return document.getElementById(id);
  }

  function toNum(v) {
    v = Number(v);
    return Number.isFinite(v) ? v : 0;
  }

  function fmt(v) {
    return toNum(v).toLocaleString("en-US");
  }

  function renderV3(payload) {
    if (!payload) return;

    var sev = payload.by_severity || {};

    var total = toNum(payload.total_findings);
    var crit  = toNum(sev.CRITICAL);
    var high  = toNum(sev.HIGH);
    var med   = toNum(sev.MEDIUM);
    var low   = toNum(sev.LOW);
    var info  = toNum(sev.INFO);
    var trace = toNum(sev.TRACE);

    if ($("vsp-kpi-total"))    $("vsp-kpi-total").textContent    = fmt(total);
    if ($("vsp-kpi-critical")) $("vsp-kpi-critical").textContent = fmt(crit);
    if ($("vsp-kpi-high"))     $("vsp-kpi-high").textContent     = fmt(high);
    if ($("vsp-kpi-medium"))   $("vsp-kpi-medium").textContent   = fmt(med);
    if ($("vsp-kpi-low"))      $("vsp-kpi-low").textContent      = fmt(low);
    if ($("vsp-kpi-info"))     $("vsp-kpi-info").textContent     = fmt(info);
    if ($("vsp-kpi-trace"))    $("vsp-kpi-trace").textContent    = fmt(trace);

    var score = toNum(payload.security_score);
    if ($("vsp-kpi-security-score")) {
      $("vsp-kpi-security-score").textContent = score.toFixed(1);
    }

    if ($("vsp-kpi-top-tool")) {
      $("vsp-kpi-top-tool").textContent = payload.top_risky_tool || "-";
    }
    if ($("vsp-kpi-top-cwe")) {
      $("vsp-kpi-top-cwe").textContent = payload.top_cwe || "-";
    }
    if ($("vsp-kpi-top-module")) {
      $("vsp-kpi-top-module").textContent = payload.top_module || "-";
    }
  }

  function fetchAndBindV3() {
    fetch(API_URL, { headers: { "Accept": "application/json" } })
      .then(function (res) { return res.json(); })
      .then(function (data) {
        if (!data || data.ok === false) {
          console.warn("[VSP][V3_FIX] ok=false hoặc payload rỗng:", data);
          return;
        }
        renderV3(data);
        console.log("[VSP][V3_FIX] bound dashboard_v3:", {
          run_id: data.run_id,
          total_findings: data.total_findings
        });
      })
      .catch(function (err) {
        console.error("[VSP][V3_FIX] fetch error:", err);
      });
  }

  document.addEventListener("DOMContentLoaded", fetchAndBindV3);
})();

