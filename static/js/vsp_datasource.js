(function () {
  function $(id) { return document.getElementById(id); }

  function renderTotal(summary) {
    var el = $("ds-total");
    if (!el || !summary) return;
    el.textContent = summary.total || 0;
  }

  function renderSeverityChart(counts) {
    var canvas = $("ds-severity-chart");
    if (!canvas || !window.Chart || !counts) return;
    var ctx = canvas.getContext("2d");
    if (!ctx) return;

    var labels = Object.keys(counts);
    var values = labels.map(function (k) { return counts[k]; });

    new Chart(ctx, {
      type: "doughnut",
      data: { labels: labels, datasets: [{ data: values }] },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { position: "bottom" },
          title: { display: true, text: "Severity distribution (current run)" }
        }
      }
    });
  }

  function renderToolsChart(counts) {
    var canvas = $("ds-tools-chart");
    if (!canvas || !window.Chart || !counts) return;
    var ctx = canvas.getContext("2d");
    if (!ctx) return;

    var pairs = Object.keys(counts).map(function (k) {
      return { tool: k, value: counts[k] };
    }).sort(function (a, b) { return b.value - a.value; });

    var labels = pairs.map(function (p) { return p.tool; });
    var values = pairs.map(function (p) { return p.value; });

    new Chart(ctx, {
      type: "bar",
      data: { labels: labels, datasets: [{ data: values }] },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        indexAxis: "y",
        plugins: {
          legend: { display: false },
          title: { display: true, text: "Findings by tool" }
        },
        scales: { x: { beginAtZero: true } }
      }
    });
  }

  function renderTable(rows) {
    var tbody = $("ds-table-body");
    if (!tbody) return;
    tbody.innerHTML = "";

    if (!Array.isArray(rows) || rows.length === 0) {
      var tr = document.createElement("tr");
      var td = document.createElement("td");
      td.colSpan = 7;
      td.textContent = "No findings.";
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }

    var limited = rows.slice(0, 200);
    limited.forEach(function (row, idx) {
      var tr = document.createElement("tr");
      function td(text) {
        var c = document.createElement("td");
        c.textContent = text == null ? "" : String(text);
        return c;
      }
      tr.appendChild(td(idx + 1));
      tr.appendChild(td(row.severity || row.SEVERITY || ""));
      tr.appendChild(td(row.tool || row.TOOL || ""));
      tr.appendChild(td(row.rule || row.RULE_ID || row.rule_id || ""));
      var fileText = (row.file || row.FILE || "") + (row.line || row.LINE ? (":" + (row.line || row.LINE)) : "");
      tr.appendChild(td(fileText));
      tr.appendChild(td(row.cwe || row.CWE || ""));
      tr.appendChild(td(row.message || row.MESSAGE || ""));
      tbody.appendChild(tr);
    });
  }

  function normalizeRows(data) {
    // Nếu BE trả sẵn rows thì dùng luôn
    if (Array.isArray(data.rows) && data.rows.length > 0) return data.rows;
    // Nếu không, nhưng có findings dạng list thì map sang rows
    if (Array.isArray(data.findings)) {
      return data.findings.map(function (item) {
        return {
          severity: (item.severity || "").toUpperCase(),
          tool: (item.tool || "").toLowerCase(),
          rule: item.rule_id || item.rule || "",
          file: item.file || "",
          line: item.line || 0,
          cwe: item.cwe || item.cve || "",
          message: item.message || item.description || ""
        };
      });
    }
    return [];
  }

  function loadDataSource() {
    fetch("/api/vsp/datasource")
      .then(function (resp) { return resp.json(); })
      .then(function (data) {
        if (!data) {
          console.warn("[VSP][DATASOURCE] empty response");
          return;
        }
        // Không còn if (!data.ok) return nữa, BE có thể không gửi field ok
        var summary = data.summary || {
          total: data.total || 0,
          severity_counts: data.severity_counts || {},
          tool_counts: data.tool_counts || {}
        };

        console.info("[VSP][DATASOURCE] run:", data.run_id, "total:", summary.total);

        renderTotal(summary);
        renderSeverityChart(summary.severity_counts);
        renderToolsChart(summary.tool_counts);

        var rows = normalizeRows(data);
        renderTable(rows);
      })
      .catch(function (err) {
        console.error("[VSP][DATASOURCE] fetch error:", err);
      });
  }

  document.addEventListener("DOMContentLoaded", function () {
    loadDataSource();
  });
})();
