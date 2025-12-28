document.addEventListener("DOMContentLoaded", function () {
  const pre = document.getElementById("ds-summary-json");
  const container = document.querySelector("#ds-summary-tables .ds-summary-grid");
  if (!pre || !container) {
    return;
  }

  let text = pre.textContent || pre.innerText || "";
  text = text.trim();
  if (!text) {
    return;
  }

  let obj;
  try {
    obj = JSON.parse(text);
  } catch (e) {
    console.warn("[DataSource] Không parse được summary JSON:", e);
    return;
  }

  // Lấy tổng và đếm theo severity
  let sev =
    obj.severity_counts ||
    obj.SEVERITY_COUNTS ||
    obj.by_severity ||
    {};
  const order = ["CRITICAL", "HIGH", "MEDIUM", "LOW"];
  const sevRows = order.map((k) => ({
    name: k,
    value: Number(sev[k] || 0),
  }));

  // Lấy đếm theo tool
  let byTool =
    obj.by_tool ||
    obj.BY_TOOL ||
    obj.tools ||
    {};
  let toolRows = [];

  if (Array.isArray(byTool)) {
    // hiếm gặp: list tool
    toolRows = byTool.map((t) => ({
      name: t.tool || t.name || "-",
      total: Number(t.total || t.count || 0),
    }));
  } else if (typeof byTool === "object") {
    for (const [name, v] of Object.entries(byTool)) {
      if (!v || typeof v !== "object") continue;
      const total =
        Number(v.total || v.count || 0) ||
        (v.by_severity
          ? Object.values(v.by_severity).reduce(
              (a, b) => a + Number(b || 0),
              0
            )
          : 0);
      toolRows.push({ name, total });
    }
  }

  toolRows.sort((a, b) => b.total - a.total);

  // Helper tạo bảng
  function makeTable(title, headers, rows) {
    const wrapper = document.createElement("div");
    wrapper.className = "ds-summary-card";

    const h = document.createElement("h5");
    h.textContent = title;
    wrapper.appendChild(h);

    const table = document.createElement("table");
    table.className = "sb-table sb-table-compact";

    const thead = document.createElement("thead");
    const trh = document.createElement("tr");
    headers.forEach((h) => {
      const th = document.createElement("th");
      th.textContent = h;
      trh.appendChild(th);
    });
    thead.appendChild(trh);
    table.appendChild(thead);

    const tbody = document.createElement("tbody");
    if (!rows.length) {
      const tr = document.createElement("tr");
      const td = document.createElement("td");
      td.colSpan = headers.length;
      td.textContent = "No data.";
      tr.appendChild(td);
      tbody.appendChild(tr);
    } else {
      rows.forEach((r) => {
        const tr = document.createElement("tr");
        Object.values(r).forEach((v) => {
          const td = document.createElement("td");
          td.textContent = v;
          tr.appendChild(td);
        });
        tbody.appendChild(tr);
      });
    }
    table.appendChild(tbody);
    wrapper.appendChild(table);
    return wrapper;
  }

  container.innerHTML = "";

  const total =
    obj.total_findings || obj.TOTAL_FINDINGS || obj.total || 0;

  // Bảng severity
  const sevRowsDisplay = sevRows.map((r) => ({
    Severity: r.name,
    Count: r.value,
  }));
  const sevTable = makeTable(
    `Summary by severity (total ${total})`,
    ["Severity", "Count"],
    sevRowsDisplay
  );
  container.appendChild(sevTable);

  // Bảng Tool
  const toolRowsDisplay = toolRows.map((t) => ({
    Tool: t.name,
    Total: t.total,
  }));
  const toolTable = makeTable(
    "Summary by tool",
    ["Tool", "Total findings"],
    toolRowsDisplay
  );
  container.appendChild(toolTable);
});
