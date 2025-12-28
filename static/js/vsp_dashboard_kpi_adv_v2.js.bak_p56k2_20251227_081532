/* VSP_P0_CIO_SCRUB_NA_ALL_V1P4C */
/* ---------------------------------------------------------
 * VSP CIO VIEW – Advanced KPI (Top risks + Noisy paths)
 * Không sửa layout, chỉ inject data vào 2 bảng:
 *  - "Top risk findings"
 *  - "Top noisy paths"
 * Tự tìm bảng bằng heading text, không cần thêm id.
 * --------------------------------------------------------- */

(function () {
  "use strict";

  function dbg() {
    if (window.console && console.log) {
      console.log.apply(console, arguments);
    }
  }

  function findTbodyByHeading(keyword) {
    keyword = (keyword || "").toLowerCase();
    if (!keyword) return null;

    var headings = document.querySelectorAll("h2, h3, h4, h5");
    for (var i = 0; i < headings.length; i++) {
      var h = headings[i];
      var txt = (h.textContent || "").toLowerCase();
      if (txt.indexOf(keyword) !== -1) {
        // tìm container gần nhất có table
        var container = h.closest("section, article, div") || h.parentElement;
        if (!container) continue;
        var tbody = container.querySelector("tbody");
        if (tbody) {
          return tbody;
        }
      }
    }
    return null;
  }

  /* ------------------------------
     TOP RISK FINDINGS
     (CRITICAL + HIGH)
  ------------------------------ */
  function loadTopRiskFindings() {
    var severities = ["CRITICAL", "HIGH"];
    var promises = [];

    for (var i = 0; i < severities.length; i++) {
      (function (sev) {
        var url = "/api/vsp/datasource_v2?severity=" +
                  encodeURIComponent(sev) + "&limit=50";
        dbg("[VSP][ADV] top risks GET", url);
        var p = fetch(url)
          .then(function (r) { return r.json(); })
          .catch(function (e) {
            console.error("[VSP][ADV] top risks fetch ERR (" + sev + "):", e);
            return null;
          });
        promises.push(p);
      })(severities[i]);
    }

    Promise.all(promises).then(function (results) {
      var tbody = findTbodyByHeading("top risk findings");
      if (!tbody) {
        dbg("[VSP][ADV] Không tìm thấy bảng 'Top risk findings' trong DOM.");
        return;
      }

      var allItems = [];
      for (var i = 0; i < results.length; i++) {
        var res = results[i];
        if (!res || res.ok === false || !Array.isArray(res.items)) continue;
        allItems = allItems.concat(res.items);
      }

      if (!allItems.length) {
        tbody.innerHTML =
          '<tr><td colspan="4">No CRITICAL/HIGH findings.</td></tr>';
        return;
      }

      // sort: CRITICAL trước HIGH
      var weight = { CRITICAL: 2, HIGH: 1 };
      allItems.sort(function (a, b) {
        var sa = a.severity_effective || a.severity || "HIGH";
        var sb = b.severity_effective || b.severity || "HIGH";
        var wa = weight[sa] || 0;
        var wb = weight[sb] || 0;
        if (wa !== wb) return wb - wa;
        return 0;
      });

      // Lấy TOP 10
      allItems = allItems.slice(0, 10);

      tbody.innerHTML = "";
      for (var j = 0; j < allItems.length; j++) {
        var it = allItems[j];
        var sev  = it.severity_effective || it.severity || '0';
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
      }
    });
  }

  /* ------------------------------
     TOP NOISY PATHS
     (MEDIUM / LOW / INFO / TRACE)
  ------------------------------ */
  function loadTopNoisyPaths() {
    var severities = ["MEDIUM", "LOW", "INFO", "TRACE"];
    var promises = [];

    for (var i = 0; i < severities.length; i++) {
      (function (sev) {
        var url = "/api/vsp/datasource_v2?severity=" +
                  encodeURIComponent(sev) + "&limit=200";
        dbg("[VSP][ADV] noisy paths GET", url);
        var p = fetch(url)
          .then(function (r) { return r.json(); })
          .catch(function (e) {
            console.error("[VSP][ADV] noisy paths fetch ERR (" + sev + "):", e);
            return null;
          });
        promises.push(p);
      })(severities[i]);
    }

    Promise.all(promises).then(function (results) {
      var tbody = findTbodyByHeading("top noisy paths");
      if (!tbody) {
        dbg("[VSP][ADV] Không tìm thấy bảng 'Top noisy paths' trong DOM.");
        return;
      }

      var counts = {}; // path/file -> total

      for (var i = 0; i < results.length; i++) {
        var res = results[i];
        if (!res || res.ok === false || !Array.isArray(res.items)) continue;

        for (var j = 0; j < res.items.length; j++) {
          var it = res.items[j];
          var key = it.file || it.path || "";
          if (!key) continue;
          if (!counts[key]) counts[key] = 0;
          counts[key] += 1;
        }
      }

      var paths = [];
      for (var k in counts) {
        if (!counts.hasOwnProperty(k)) continue;
        paths.push({ path: k, total: counts[k] });
      }

      if (!paths.length) {
        tbody.innerHTML =
          '<tr><td colspan="3">No noisy paths (MEDIUM/LOW/INFO/TRACE).</td></tr>';
        return;
      }

      // sort desc theo total
      paths.sort(function (a, b) {
        return b.total - a.total;
      });

      // helper noise level
      function noiseLevel(total) {
        if (total >= 20) return "HIGH";
        if (total >= 10) return "MEDIUM";
        if (total >= 3)  return "LOW";
        return "MINOR";
      }

      // Lấy TOP 10
      paths = paths.slice(0, 10);

      tbody.innerHTML = "";
      for (var p = 0; p < paths.length; p++) {
        var e = paths[p];
        var tr = document.createElement("tr");
        tr.innerHTML =
          "<td>" + e.path + "</td>" +
          "<td>" + e.total + "</td>" +
          "<td>" + noiseLevel(e.total) + "</td>";
        tbody.appendChild(tr);
      }
    });
  }

  /* ------------------------------
     INIT – KHÔNG ĐỤNG JS CŨ
  ------------------------------ */
  function initAdvKpi() {
    dbg("[VSP][ADV] init advanced KPI (top risks + noisy paths)");
    loadTopRiskFindings();
    loadTopNoisyPaths();
  }

  document.addEventListener("DOMContentLoaded", initAdvKpi);
})();
