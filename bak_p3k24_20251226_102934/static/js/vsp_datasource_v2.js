// === VSP DATASOURCE – FIX V3 ===

function loadDataSource() {
  fetch("/api/vsp/datasource_v2?limit=5000")
    .then(r => r.json())
    .then(json => {
      if (!json.ok) return;
      const tbody = $("#datasource-body");
      tbody.empty();

      json.items.forEach(item => {
        const sev = (item.severity_effective || "INFO").toLowerCase();
        const row = `
          <tr>
            <td class="sev-${sev}">${item.severity_effective}</td>
            <td>${item.tool}</td>
            <td>${item.file}</td>
            <td>${item.line || "-"}</td>
            <td>${item.cwe || "-"}</td>
            <td>${item.description || "-"}</td>
          </tr>
        `;
        tbody.append(row);
      });
    })
    .catch(err => console.error("[DATASOURCE] Error:", err));
}

document.addEventListener("DOMContentLoaded", loadDataSource);
