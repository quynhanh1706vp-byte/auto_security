(function () {
  console.log("[VSP_DAST] vsp_dast_history_v1.js loaded");
  const tableBody = document.getElementById("vsp-dast-history-body");

  async function loadHistory() {
    if (!tableBody) return;
    try {
      const resp = await fetch("/api/vsp/dast/history");
      const data = await resp.json();
      if (!data.ok) {
        console.warn("[VSP_DAST] history not ok", data);
        return;
      }
      tableBody.innerHTML = "";
      data.items.forEach(item => {
        const tr = document.createElement("tr");
        tr.innerHTML = `
          <td>${item.run_id}</td>
          <td>${item.url}</td>
          <td>${item.engine}</td>
          <td>${item.status}</td>
          <td>${item.created_at || ""}</td>
        `;
        tableBody.appendChild(tr);
      });
    } catch (err) {
      console.error("[VSP_DAST] loadHistory error", err);
    }
  }

  document.addEventListener("DOMContentLoaded", loadHistory);
})();
